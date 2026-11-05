import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:loading/core/app_exception.dart';
import 'package:loading/features/media/data/browser_headers.dart';
import 'package:loading/features/media/data/part_planner.dart';

class RemoteFileInfo {
  const RemoteFileInfo({
    required this.totalBytes,
    required this.acceptRanges,
    required this.contentType,
  });

  final int? totalBytes;
  final bool acceptRanges;
  final String? contentType;
}

class PartProgress {
  const PartProgress({
    required this.partIndex,
    required this.partCount,
    required this.bytesDone,
    required this.bytesTotal,
    required this.merging,
  });

  final int partIndex;
  final int partCount;
  final int bytesDone;
  final int bytesTotal;
  final bool merging;
}

class FileDownloader {
  FileDownloader({
    Dio? dio,
    this.partSize = kPartSizeBytes,
    this.splitThreshold = kSplitThresholdBytes,
    this.parallel = kParallelParts,
  }) : dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(minutes: 2),
               followRedirects: true,
               maxRedirects: 10,
             ),
           );

  final Dio dio;
  final int partSize;
  final int splitThreshold;
  final int parallel;

  Future<RemoteFileInfo> probe({
    required String url,
    required String referer,
    CancelToken? cancelToken,
    Map<String, String>? extraHeaders,
  }) async {
    try {
      final response = await dio.head<void>(
        url,
        cancelToken: cancelToken,
        options: Options(
          headers: _headers(referer: referer, extraHeaders: extraHeaders),
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      return _infoFromHeaders(
        headers: response.headers,
        statusCode: response.statusCode,
      );
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) throw asAppException(error);
      final code = error.response?.statusCode;
      final headRejected =
          code == 400 || code == 403 || code == 405 || code == 501;
      if (!headRejected && error.type == DioExceptionType.connectionError) {
        throw asAppException(error);
      }
      if (!headRejected && error.type == DioExceptionType.connectionTimeout) {
        throw asAppException(error);
      }
    }

    final probeCancel = CancelToken();
    try {
      final response = await dio.get<ResponseBody>(
        url,
        cancelToken: probeCancel,
        options: Options(
          responseType: ResponseType.stream,
          headers: _headers(
            referer: referer,
            range: 'bytes=0-0',
            extraHeaders: extraHeaders,
          ),
          validateStatus: (status) => status == 200 || status == 206,
        ),
      );
      final info = _infoFromHeaders(
        headers: response.headers,
        statusCode: response.statusCode,
        ranged: true,
      );
      final body = response.data;
      if (response.statusCode == 206) {
        if (body != null) await body.stream.drain<void>();
      } else {
        probeCancel.cancel();
      }
      return info;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) && probeCancel.isCancelled) {
        throw const AppException('อ่านขนาดไฟล์ไม่ได้');
      }
      final code = error.response?.statusCode;
      // CDN บางเจ้าตอบ 400 เมื่อถูกขอเป็นช่วงไบต์ ทั้งที่ GET ทั้งไฟล์ได้
      if (code == 400 || code == 403 || code == 416) {
        return const RemoteFileInfo(
          totalBytes: null,
          acceptRanges: false,
          contentType: null,
        );
      }
      throw asAppException(error);
    }
  }

  Future<File> download({
    required String url,
    required Directory directory,
    required String fileName,
    required String referer,
    RemoteFileInfo? known,
    CancelToken? cancelToken,
    Map<String, String>? extraHeaders,
    void Function(PartProgress progress)? onProgress,
  }) async {
    final info =
        known ??
        await probe(
          url: url,
          referer: referer,
          cancelToken: cancelToken,
          extraHeaders: extraHeaders,
        );
    final total = info.totalBytes;
    final output = File('${directory.path}/$fileName');
    if (await output.exists()) await output.delete();

    if (total == 0) throw const AppException('ไฟล์ไม่มีข้อมูลให้โหลด');
    if (total == null || !info.acceptRanges || total <= splitThreshold) {
      await _saveWhole(
        url: url,
        file: output,
        referer: referer,
        cancelToken: cancelToken,
        total: total,
        extraHeaders: extraHeaders,
        onProgress: onProgress,
      );
      return output;
    }

    final ranges = planParts(totalBytes: total, partSize: partSize);
    final partFiles = <File>[
      for (var i = 0; i < ranges.length; i++)
        File('${directory.path}/$fileName.part${i.toString().padLeft(3, '0')}'),
    ];
    final received = List<int>.filled(ranges.length, 0);

    void report(int partIndex, {required bool merging}) {
      var done = 0;
      for (final value in received) {
        done += value;
      }
      onProgress?.call(
        PartProgress(
          partIndex: partIndex,
          partCount: ranges.length,
          bytesDone: done,
          bytesTotal: total,
          merging: merging,
        ),
      );
    }

    try {
      // part แรกตัดสินว่าเซิร์ฟเวอร์ยอมแบ่งช่วงไบต์หรือส่งทั้งไฟล์
      final first = await _downloadRange(
        url: url,
        range: ranges.first,
        file: partFiles.first,
        referer: referer,
        extraHeaders: extraHeaders,
        cancelToken: cancelToken,
        onBytes: (count) {
          received[0] = count;
          report(0, merging: false);
        },
      );
      if (first.status == 200) {
        await _replace(partFiles.first, output);
        final size = await output.length();
        if (size != total) {
          await output.delete();
          throw AppException('ได้ไฟล์ $size ไบต์ จากที่เซิร์ฟเวอร์บอก $total');
        }
        return output;
      }
      if (first.status != 206 || first.bytes != ranges.first.length) {
        throw AppException('part 1 ได้รหัส ${first.status} ไม่ครบช่วงที่ขอ');
      }

      Object? firstError;
      await _runPool(
        parallel,
        [
          for (var i = 1; i < ranges.length; i++)
            () async {
              final result = await _downloadRange(
                url: url,
                range: ranges[i],
                file: partFiles[i],
                referer: referer,
                extraHeaders: extraHeaders,
                cancelToken: cancelToken,
                onBytes: (count) {
                  received[i] = count;
                  report(i, merging: false);
                },
              );
              if (result.status != 206 || result.bytes != ranges[i].length) {
                throw AppException(
                  'part ${i + 1} ได้รหัส ${result.status} ไม่ครบช่วงที่ขอ',
                );
              }
            },
        ],
        onError: (error) {
          firstError ??= error;
          if (cancelToken != null && !cancelToken.isCancelled) {
            cancelToken.cancel();
          }
        },
      );
      final poolError = firstError;
      if (poolError != null) throw poolError;

      report(ranges.length - 1, merging: true);
      await _concat(partFiles, output);
      final size = await output.length();
      if (size != total) {
        await output.delete();
        throw AppException('ต่อ part แล้วได้ $size ไบต์ แต่ไฟล์จริงคือ $total');
      }
      for (final part in partFiles) {
        if (await part.exists()) await part.delete();
      }
      return output;
    } catch (error) {
      if (await output.exists()) await output.delete();
      for (final part in partFiles) {
        if (await part.exists()) await part.delete();
      }
      throw asAppException(error);
    }
  }

  Map<String, String> _headers({
    required String referer,
    String? range,
    Map<String, String>? extraHeaders,
  }) {
    final headers = browserHeaders(referer: referer, range: range);
    final extra = extraHeaders;
    if (extra != null) headers.addAll(extra);
    return headers;
  }

  RemoteFileInfo _infoFromHeaders({
    required Headers headers,
    required int? statusCode,
    bool ranged = false,
  }) {
    final length = int.tryParse(
      headers.value(Headers.contentLengthHeader) ?? '',
    );
    final accept =
        headers.value('accept-ranges')?.toLowerCase().contains('bytes') ??
        false;
    final type = headers.value(Headers.contentTypeHeader);
    if (ranged && statusCode == 206) {
      final total = _totalFromContentRange(headers.value('content-range'));
      return RemoteFileInfo(
        totalBytes: total,
        acceptRanges: true,
        contentType: type,
      );
    }
    return RemoteFileInfo(
      totalBytes: length,
      acceptRanges: accept,
      contentType: type,
    );
  }

  int? _totalFromContentRange(String? header) {
    if (header == null) return null;
    final match = RegExp(r'/(\d+)\s*$').firstMatch(header);
    final raw = match?.group(1);
    if (raw == null) return null;
    return int.tryParse(raw);
  }

  Future<void> _saveWhole({
    required String url,
    required File file,
    required String referer,
    required CancelToken? cancelToken,
    required int? total,
    required Map<String, String>? extraHeaders,
    required void Function(PartProgress progress)? onProgress,
  }) async {
    final response = await dio.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: _headers(referer: referer, extraHeaders: extraHeaders),
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    );
    final body = response.data;
    if (body == null) throw const AppException('เซิร์ฟเวอร์ไม่ส่งข้อมูลไฟล์');
    // ขนาดจาก HEAD ของ CDN บ่อยครั้งใหญ่กว่าไฟล์ที่ GET ส่งมาจริง และรอบ GET ไม่ใส่ content-length
    final declared = int.tryParse(
      response.headers.value(Headers.contentLengthHeader) ?? '',
    );
    final count = await _writeStream(
      stream: body.stream,
      file: file,
      onBytes: (bytes) {
        onProgress?.call(
          PartProgress(
            partIndex: 0,
            partCount: 1,
            bytesDone: bytes,
            bytesTotal: declared ?? total ?? bytes,
            merging: false,
          ),
        );
      },
    );
    if (declared != null && count != declared) {
      if (await file.exists()) await file.delete();
      throw AppException('ได้ไฟล์ $count ไบต์ จากที่เซิร์ฟเวอร์บอก $declared');
    }
  }

  Future<_RangeResult> _downloadRange({
    required String url,
    required ByteRange range,
    required File file,
    required String referer,
    required Map<String, String>? extraHeaders,
    required CancelToken? cancelToken,
    required void Function(int count) onBytes,
  }) async {
    final response = await dio.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: _headers(
          referer: referer,
          range: range.header,
          extraHeaders: extraHeaders,
        ),
        validateStatus: (status) => status == 200 || status == 206,
      ),
    );
    final body = response.data;
    final status = response.statusCode ?? 0;
    if (body == null) throw AppException('part ตอบรหัส $status แต่ไม่มีข้อมูล');
    final count = await _writeStream(
      stream: body.stream,
      file: file,
      onBytes: onBytes,
    );
    return _RangeResult(status, count);
  }

  Future<int> _writeStream({
    required Stream<Uint8List> stream,
    required File file,
    required void Function(int count) onBytes,
  }) async {
    final sink = file.openWrite();
    var count = 0;
    try {
      await for (final chunk in stream) {
        count += chunk.length;
        sink.add(chunk);
        onBytes(count);
      }
      await sink.flush();
    } catch (error) {
      await sink.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }
    await sink.close();
    return count;
  }

  Future<void> _concat(List<File> parts, File output) async {
    final sink = output.openWrite();
    try {
      for (final part in parts) {
        await sink.addStream(part.openRead());
      }
      await sink.flush();
    } catch (error) {
      await sink.close();
      if (await output.exists()) await output.delete();
      rethrow;
    }
    await sink.close();
  }

  Future<void> _replace(File source, File output) async {
    if (await output.exists()) await output.delete();
    await source.rename(output.path);
  }

  Future<void> _runPool(
    int width,
    List<Future<void> Function()> jobs, {
    required void Function(Object error) onError,
  }) async {
    if (jobs.isEmpty) return;
    var cursor = 0;
    Object? firstError;
    Future<void> worker() async {
      while (cursor < jobs.length && firstError == null) {
        final index = cursor;
        cursor += 1;
        try {
          await jobs[index]();
        } catch (error) {
          firstError ??= error;
          onError(error);
        }
      }
    }

    final count = width < jobs.length ? width : jobs.length;
    await Future.wait(List.generate(count, (_) => worker()));
    final error = firstError;
    if (error != null) throw error;
  }
}

class _RangeResult {
  const _RangeResult(this.status, this.bytes);

  final int status;
  final int bytes;
}
