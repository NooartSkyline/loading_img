import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:loading/core/app_exception.dart';
import 'package:loading/features/browser/data/hls_crypto.dart';
import 'package:loading/features/browser/data/hls_playlist.dart';
import 'package:loading/features/browser/data/track_mux.dart';
import 'package:loading/features/browser/data/ts_mp4.dart';
import 'package:loading/features/browser/model/found_stream.dart';
import 'package:loading/features/media/data/browser_headers.dart';
import 'package:loading/features/media/data/embedded_text.dart';
import 'package:loading/features/media/data/file_downloader.dart';
import 'package:loading/features/media/model/media_kind.dart';
import 'package:path_provider/path_provider.dart';

class StreamProgress {
  const StreamProgress({
    required this.done,
    required this.total,
    required this.label,
  });

  final int done;
  final int total;
  final String label;

  double? get fraction {
    if (total <= 0) return null;
    final value = done / total;
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }
}

class StreamSaver {
  StreamSaver({
    Dio? dio,
    FileDownloader? files,
    TrackMux? mux,
    Future<Directory> Function()? workDirectory,
  }) : dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(minutes: 2),
               followRedirects: true,
               maxRedirects: 8,
             ),
           ),
       files = files ?? FileDownloader(),
       mux = mux ?? const TrackMux(),
       _workDirectory = workDirectory ?? getTemporaryDirectory;

  final Dio dio;
  final FileDownloader files;
  final TrackMux mux;
  final Future<Directory> Function() _workDirectory;

  Future<File> fetch({
    required FoundStream stream,
    required String referer,
    required String? cookie,
    String? userAgent,
    required CancelToken cancelToken,
    required void Function(StreamProgress progress) onProgress,
  }) async {
    final root = await _workDirectory();
    final directory = Directory(
      '${root.path}/browser_${DateTime.now().microsecondsSinceEpoch}',
    );
    await directory.create(recursive: true);
    try {
      if (stream.playlist) {
        return await _playlist(
          url: Uri.parse(stream.url),
          referer: referer,
          cookie: cookie,
          userAgent: userAgent,
          directory: directory,
          cancelToken: cancelToken,
          onProgress: onProgress,
        );
      }
      onProgress(
        const StreamProgress(done: 0, total: 0, label: 'กำลังโหลดวิดีโอ'),
      );
      final file = await files.download(
        url: stream.url,
        directory: directory,
        fileName: safeFileName('video.mp4'),
        referer: referer,
        extraHeaders: _downloadHeaders(cookie, userAgent),
        cancelToken: cancelToken,
        onProgress: (part) {
          onProgress(
            StreamProgress(
              done: part.bytesDone,
              total: part.bytesTotal,
              label: part.merging ? 'กำลังต่อไฟล์' : 'กำลังโหลดวิดีโอ',
            ),
          );
        },
      );
      final audioUrl = stream.audioUrl;
      if (audioUrl == null) return file;
      onProgress(
        const StreamProgress(done: 0, total: 0, label: 'กำลังโหลดเสียง'),
      );
      final audio = await files.download(
        url: audioUrl,
        directory: directory,
        fileName: safeFileName('audio.m4a'),
        referer: referer,
        extraHeaders: _downloadHeaders(cookie, userAgent),
        cancelToken: cancelToken,
        onProgress: (part) {
          onProgress(
            StreamProgress(
              done: part.bytesDone,
              total: part.bytesTotal,
              label: 'กำลังโหลดเสียง',
            ),
          );
        },
      );
      onProgress(
        const StreamProgress(done: 0, total: 0, label: 'กำลังรวมไฟล์'),
      );
      final output = File('${directory.path}/${safeFileName('movie.mp4')}');
      await mux.combine(
        videoPath: file.path,
        audioPath: audio.path,
        outputPath: output.path,
      );
      return output;
    } catch (error) {
      if (await directory.exists()) await directory.delete(recursive: true);
      throw asAppException(error);
    }
  }

  Future<int?> measure({
    required FoundStream stream,
    required String referer,
    String? userAgent,
    CancelToken? cancelToken,
  }) async {
    if (!stream.playlist || !stream.url.toLowerCase().contains('.m3u8')) {
      final video = await _probedSize(
        stream.url,
        referer,
        userAgent,
        cancelToken,
      );
      final audioUrl = stream.audioUrl;
      if (audioUrl == null) {
        return video;
      }
      final audio = await _probedSize(
        audioUrl,
        referer,
        userAgent,
        cancelToken,
      );
      if (video == null && audio == null) {
        return null;
      }
      return (video ?? 0) + (audio ?? 0);
    }
    try {
      final token = cancelToken ?? CancelToken();
      final root = Uri.parse(stream.url);
      var playlist = parseHlsPlaylist(
        await _text(root, referer, null, userAgent, token),
        root,
      );
      var bandwidth = 0;
      if (playlist.isMaster) {
        final variant = playlist.bestVariant;
        bandwidth = variant.bandwidth;
        playlist = parseHlsPlaylist(
          await _text(variant.uri, referer, null, userAgent, token),
          variant.uri,
        );
      }
      var duration = 0.0;
      for (final segment in playlist.segments) {
        duration += segment.duration ?? 0;
      }
      if (bandwidth <= 0 || duration <= 0) return null;
      return (duration * bandwidth / 8).round();
    } on AppException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<int?> _probedSize(
    String url,
    String referer,
    String? userAgent,
    CancelToken? cancelToken,
  ) async {
    final info = await files.probe(
      url: url,
      referer: referer,
      cancelToken: cancelToken,
      extraHeaders: _downloadHeaders(null, userAgent),
    );
    final bytes = info.totalBytes;
    if (bytes == null || bytes <= 0) return null;
    return bytes;
  }

  Future<File> _playlist({
    required Uri url,
    required String referer,
    required String? cookie,
    required String? userAgent,
    required Directory directory,
    required CancelToken cancelToken,
    required void Function(StreamProgress progress) onProgress,
  }) async {
    onProgress(
      const StreamProgress(done: 0, total: 0, label: 'กำลังอ่านสตรีม'),
    );
    final payload = await _bytes(url, referer, cookie, userAgent, cancelToken);
    if (_mp4(payload)) {
      final file = File('${directory.path}/${safeFileName('video.mp4')}');
      await file.writeAsBytes(payload, flush: true);
      return file;
    }
    final body = utf8.decode(payload, allowMalformed: true).trimLeft();
    if (!body.startsWith('#EXTM3U')) {
      throw const AppException('สตรีมนี้ไม่ใช่รายการวิดีโอที่ใช้โหลดได้');
    }
    var playlist = parseHlsPlaylist(body, url);
    Uri? audioUri;
    if (playlist.isMaster) {
      final variant = playlist.bestVariant;
      audioUri = variant.audio;
      playlist = parseHlsPlaylist(
        await _text(variant.uri, referer, cookie, userAgent, cancelToken),
        variant.uri,
      );
    }
    final video = await _materialize(
      playlist: playlist,
      referer: referer,
      cookie: cookie,
      userAgent: userAgent,
      directory: directory,
      cancelToken: cancelToken,
      onProgress: onProgress,
      name: 'stream',
    );
    if (audioUri == null) {
      return video;
    }
    onProgress(
      const StreamProgress(done: 0, total: 0, label: 'กำลังโหลดเสียง'),
    );
    var audioPlaylist = parseHlsPlaylist(
      await _text(audioUri, referer, cookie, userAgent, cancelToken),
      audioUri,
    );
    if (audioPlaylist.isMaster) {
      final variant = audioPlaylist.bestVariant;
      audioPlaylist = parseHlsPlaylist(
        await _text(variant.uri, referer, cookie, userAgent, cancelToken),
        variant.uri,
      );
    }
    final audio = await _materialize(
      playlist: audioPlaylist,
      referer: referer,
      cookie: cookie,
      userAgent: userAgent,
      directory: directory,
      cancelToken: cancelToken,
      onProgress: onProgress,
      name: 'audio',
    );
    onProgress(const StreamProgress(done: 0, total: 0, label: 'กำลังรวมไฟล์'));
    final movie = File('${directory.path}/${safeFileName('movie.mp4')}');
    await mux.combine(
      videoPath: video.path,
      audioPath: audio.path,
      outputPath: movie.path,
    );
    return movie;
  }

  Future<File> _materialize({
    required HlsPlaylist playlist,
    required String referer,
    required String? cookie,
    required String? userAgent,
    required Directory directory,
    required CancelToken cancelToken,
    required void Function(StreamProgress progress) onProgress,
    required String name,
  }) async {
    if (playlist.segments.isEmpty) {
      throw const AppException('ไม่พบชิ้นส่วนของสตรีมนี้');
    }
    final shared = _singleFile(playlist);
    if (shared != null) {
      try {
        final whole = await _bytes(
          shared,
          referer,
          cookie,
          userAgent,
          cancelToken,
        );
        if (_mp4(whole) || (whole.isNotEmpty && whole[0] == 0x47)) {
          final file = File(
            '${directory.path}/${safeFileName('$name.${_extension(whole)}')}',
          );
          await file.writeAsBytes(whole, flush: true);
          return file;
        }
      } on AppException catch (error) {
        if (error.message == 'ยกเลิกการโหลดแล้ว') rethrow;
      }
    }
    final keys = <String, Uint8List>{};
    final parts = <File>[];
    final total = playlist.segments.length + (playlist.mapUri == null ? 0 : 1);
    var done = 0;

    Future<Uint8List> readPart(
      Uri uri,
      HlsKey? key,
      int sequence,
      HlsByteRange? range,
    ) async {
      final bytes = await _bytes(
        uri,
        referer,
        cookie,
        userAgent,
        cancelToken,
        range: range,
      );
      final plain = key == null
          ? bytes
          : decryptAes128Cbc(
              data: bytes,
              key: await _key(
                key,
                referer,
                cookie,
                userAgent,
                cancelToken,
                keys,
              ),
              iv: key.iv ?? ivForSequence(sequence),
            );
      return mediaPayload(plain);
    }

    final mapUri = playlist.mapUri;
    if (mapUri != null) {
      final bytes = await readPart(mapUri, null, 0, playlist.mapRange);
      final file = File('${directory.path}/$name-map.mp4');
      await file.writeAsBytes(bytes, flush: true);
      parts.add(file);
      done += 1;
      onProgress(
        StreamProgress(done: done, total: total, label: 'กำลังโหลดชิ้นส่วน'),
      );
    }

    for (final segment in playlist.segments) {
      final bytes = await readPart(
        segment.uri,
        segment.key,
        segment.sequence,
        segment.range,
      );
      final file = File(
        '${directory.path}/$name${parts.length.toString().padLeft(4, '0')}',
      );
      await file.writeAsBytes(bytes, flush: true);
      parts.add(file);
      done += 1;
      onProgress(
        StreamProgress(
          done: done,
          total: total,
          label: 'กำลังโหลดชิ้นส่วน $done/$total',
        ),
      );
    }

    onProgress(
      StreamProgress(done: total, total: total, label: 'กำลังต่อไฟล์'),
    );
    final sample = await parts.first.readAsBytes();
    final ext = _extension(sample);
    final output = File('${directory.path}/${safeFileName('$name.$ext')}');
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
    for (final part in parts) {
      if (await part.exists()) await part.delete();
    }
    if (ext != 'ts') return output;
    onProgress(
      const StreamProgress(done: 0, total: 0, label: 'กำลังแปลงเป็น mp4'),
    );
    final mp4 = File('${directory.path}/${safeFileName('$name.mp4')}');
    final failure = await _remuxTsPaths([output.path, mp4.path]);
    if (failure != null) {
      if (await mp4.exists()) await mp4.delete();
      throw AppException(failure);
    }
    if (await output.exists()) await output.delete();
    return mp4;
  }

  Future<Uint8List> _key(
    HlsKey key,
    String referer,
    String? cookie,
    String? userAgent,
    CancelToken cancelToken,
    Map<String, Uint8List> cache,
  ) async {
    final cached = cache[key.uri.toString()];
    if (cached != null) return cached;
    final bytes = await _bytes(
      key.uri,
      referer,
      cookie,
      userAgent,
      cancelToken,
    );
    if (bytes.length != 16) {
      throw const AppException('คีย์ของสตรีมนี้ใช้ไม่ได้');
    }
    cache[key.uri.toString()] = bytes;
    return bytes;
  }

  Future<String> _text(
    Uri uri,
    String referer,
    String? cookie,
    String? userAgent,
    CancelToken cancelToken,
  ) async {
    try {
      final response = await dio.get<String>(
        uri.toString(),
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.plain,
          headers: _requestHeaders(referer, cookie, userAgent),
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      final body = response.data;
      if (body == null || body.trim().isEmpty) {
        throw const AppException('สตรีมนี้ตอบกลับว่าง');
      }
      return body;
    } on DioException catch (error) {
      throw asAppException(error);
    }
  }

  Future<Uint8List> _bytes(
    Uri uri,
    String referer,
    String? cookie,
    String? userAgent,
    CancelToken cancelToken, {
    HlsByteRange? range,
  }) async {
    final headers = _requestHeaders(referer, cookie, userAgent);
    if (range == null) return _body(uri, headers, cancelToken);
    final end = range.offset + range.length - 1;
    try {
      final ranged = Map<String, String>.from(headers);
      ranged['Range'] = 'bytes=${range.offset}-$end';
      final response = await dio.get<List<int>>(
        uri.toString(),
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.bytes,
          headers: ranged,
          validateStatus: (status) => status == 200 || status == 206,
        ),
      );
      final sliced = _slice(response.data, response.statusCode, range);
      if (sliced != null) return sliced;
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) {
        throw asAppException(error);
      }
      final code = error.response?.statusCode;
      if (code != 400 && code != 403 && code != 416) {
        throw asAppException(error);
      }
    }
    final query = uri.query.isEmpty
        ? 'bytes=${range.offset}-$end'
        : '${uri.query}&bytes=${range.offset}-$end';
    final body = await _body(uri.replace(query: query), headers, cancelToken);
    final sliced = _slice(body, 200, range);
    if (sliced == null) {
      throw const AppException('โหลดช่วงของสตรีมไม่ได้');
    }
    return sliced;
  }

  Future<Uint8List> _body(
    Uri uri,
    Map<String, String> headers,
    CancelToken cancelToken,
  ) async {
    try {
      final response = await dio.get<List<int>>(
        uri.toString(),
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      final body = response.data;
      if (body == null || body.isEmpty) {
        throw const AppException('ชิ้นส่วนของสตรีมว่าง');
      }
      return Uint8List.fromList(body);
    } on DioException catch (error) {
      throw asAppException(error);
    }
  }

  Map<String, String> _requestHeaders(
    String referer,
    String? cookie,
    String? userAgent,
  ) {
    final headers = browserHeaders(referer: referer, userAgent: userAgent);
    final extra = _cookieHeader(cookie);
    if (extra != null) headers.addAll(extra);
    return headers;
  }

  Map<String, String>? _downloadHeaders(String? cookie, String? userAgent) {
    final headers = <String, String>{};
    final agent = userAgent?.trim();
    if (agent != null && agent.isNotEmpty) headers['User-Agent'] = agent;
    final extra = _cookieHeader(cookie);
    if (extra != null) headers.addAll(extra);
    if (headers.isEmpty) return null;
    return headers;
  }

  Map<String, String>? _cookieHeader(String? cookie) {
    final value = cookie?.trim();
    if (value == null || value.isEmpty) return null;
    return {'Cookie': value};
  }

  String _extension(Uint8List sample) {
    if (sample.length >= 8) {
      final brand = String.fromCharCodes(sample.sublist(4, 8));
      if (brand == 'ftyp') return 'mp4';
    }
    if (sample.isNotEmpty && sample[0] == 0x47) return 'ts';
    return 'mp4';
  }
}

const streamKind = MediaKind.video;

Uri? _singleFile(HlsPlaylist playlist) {
  final uris = <String>{
    if (playlist.mapUri != null) playlist.mapUri.toString(),
    for (final segment in playlist.segments) segment.uri.toString(),
  };
  if (uris.length != 1) return null;
  if (playlist.mapUri != null && playlist.mapRange == null) return null;
  for (final segment in playlist.segments) {
    if (segment.range == null) return null;
  }
  return playlist.segments.first.uri;
}

Uint8List? _slice(List<int>? raw, int? status, HlsByteRange range) {
  if (raw == null || raw.isEmpty) return null;
  final body = Uint8List.fromList(raw);
  if (status == 206 || body.length == range.length) {
    if (body.length < range.length) return null;
    return Uint8List.sublistView(body, 0, range.length);
  }
  final end = range.offset + range.length;
  if (body.length < end) return null;
  return Uint8List.sublistView(body, range.offset, end);
}

bool _mp4(Uint8List bytes) {
  final limit = bytes.length < 64 ? bytes.length - 3 : 64;
  for (var index = 0; index < limit; index++) {
    if (bytes[index] == 0x66 &&
        bytes[index + 1] == 0x74 &&
        bytes[index + 2] == 0x79 &&
        bytes[index + 3] == 0x70) {
      return true;
    }
  }
  return false;
}

Future<String?> _remuxTsPaths(List<String> paths) {
  return Isolate.run(() async {
    try {
      await remuxTsFile(paths[0], paths[1]);
      return null;
    } on AppException catch (error) {
      return error.message;
    } catch (_) {
      return 'แปลงไฟล์เข้าคลังภาพไม่ได้';
    }
  });
}
