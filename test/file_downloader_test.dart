import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loading/features/media/data/file_downloader.dart';

void main() {
  test('concatenates ranged parts back into the original file', () async {
    final bytes = List<int>.generate(200, (index) => index % 256);
    final server = await _serve(bytes, honorRange: true);
    addTearDown(() => server.close(force: true));

    final downloader = FileDownloader(
      dio: Dio(),
      partSize: 50,
      splitThreshold: 50,
      parallel: 3,
    );
    final directory = await Directory.systemTemp.createTemp('loading_parts');
    addTearDown(() => directory.delete(recursive: true));

    final file = await downloader.download(
      url: 'http://${server.address.host}:${server.port}/clip.mp4',
      directory: directory,
      fileName: 'clip.mp4',
      referer: 'https://vk.com/',
    );

    expect(await file.readAsBytes(), bytes);
    expect(directory.listSync().whereType<File>().length, 1);
  });

  test('saves the whole file when the server ignores ranges', () async {
    final bytes = List<int>.generate(200, (index) => (index * 3) % 256);
    final server = await _serve(bytes, honorRange: false);
    addTearDown(() => server.close(force: true));

    final downloader = FileDownloader(
      dio: Dio(),
      partSize: 50,
      splitThreshold: 50,
    );
    final directory = await Directory.systemTemp.createTemp('loading_whole');
    addTearDown(() => directory.delete(recursive: true));

    final file = await downloader.download(
      url: 'http://${server.address.host}:${server.port}/clip.mp4',
      directory: directory,
      fileName: 'clip.mp4',
      referer: 'https://example.com/',
    );

    expect(await file.readAsBytes(), bytes);
  });

  test(
    'keeps a finished file when the probed size is larger than the body',
    () async {
      final bytes = List<int>.generate(180, (index) => index % 256);
      final server = await _serve(
        bytes,
        honorRange: false,
        headLength: 400,
        chunkedGet: true,
      );
      addTearDown(() => server.close(force: true));

      final downloader = FileDownloader(
        dio: Dio(),
        partSize: 50,
        splitThreshold: 1024,
      );
      final directory = await Directory.systemTemp.createTemp(
        'loading_short_header',
      );
      addTearDown(() => directory.delete(recursive: true));

      final file = await downloader.download(
        url: 'http://${server.address.host}:${server.port}/photo.jpg',
        directory: directory,
        fileName: 'photo.jpg',
        referer: 'https://www.instagram.com/',
      );

      expect(await file.readAsBytes(), bytes);
    },
  );

  test('downloads the whole file when ranged probes are rejected', () async {
    final bytes = List<int>.generate(120, (index) => index % 256);
    final server = await _serve(bytes, honorRange: false, rejectRange: true);
    addTearDown(() => server.close(force: true));

    final downloader = FileDownloader(
      dio: Dio(),
      partSize: 40,
      splitThreshold: 40,
    );
    final directory = await Directory.systemTemp.createTemp(
      'loading_reject_range',
    );
    addTearDown(() => directory.delete(recursive: true));

    final file = await downloader.download(
      url: 'http://${server.address.host}:${server.port}/clip.mp4',
      directory: directory,
      fileName: 'clip.mp4',
      referer: 'https://m.vkvideo.ru/video-1_2',
    );

    expect(await file.readAsBytes(), bytes);
  });
}

Future<HttpServer> _serve(
  List<int> bytes, {
  required bool honorRange,
  int? headLength,
  bool chunkedGet = false,
  bool rejectRange = false,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final total = bytes.length;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (rejectRange && (request.method == 'HEAD' || range != null)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    if (request.method == 'HEAD') {
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(
        HttpHeaders.contentLengthHeader,
        headLength ?? total,
      );
      request.response.headers.contentType = ContentType('video', 'mp4');
      await request.response.close();
      return;
    }

    if (honorRange && range != null) {
      final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range);
      final start = int.parse(match!.group(1)!);
      final end = int.parse(match.group(2)!);
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$total',
      );
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.add(bytes.sublist(start, end + 1));
      await request.response.close();
      return;
    }

    request.response.statusCode = HttpStatus.ok;
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    if (chunkedGet) {
      request.response.headers.chunkedTransferEncoding = true;
    } else {
      request.response.headers.set(HttpHeaders.contentLengthHeader, total);
    }
    request.response.add(bytes);
    await request.response.close();
  });
  return server;
}
