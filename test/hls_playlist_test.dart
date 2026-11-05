import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loading/features/browser/data/hls_crypto.dart';
import 'package:loading/features/browser/data/hls_playlist.dart';
import 'package:loading/features/browser/data/stream_saver.dart';
import 'package:loading/features/browser/model/found_stream.dart';
import 'package:pointycastle/export.dart';

void main() {
  test('master playlist keeps the taller variant', () {
    const body = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
low/video.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720
high/video.m3u8
''';
    final playlist = parseHlsPlaylist(
      body,
      Uri.parse('https://cdn.example/playlist.m3u8'),
    );
    expect(playlist.isMaster, isTrue);
    expect(playlist.bestVariant.uri.path, '/high/video.m3u8');
  });

  test('media playlist keeps segment order and sequence', () {
    const body = '''
#EXTM3U
#EXT-X-MEDIA-SEQUENCE:4
#EXTINF:4.0,
video0.jpeg
#EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x0000000000000000000000000000002a
#EXTINF:4.0,
video1.jpeg
''';
    final playlist = parseHlsPlaylist(
      body,
      Uri.parse('https://cdn.example/720/video.m3u8'),
    );
    expect(playlist.segments.map((segment) => segment.uri.path), [
      '/720/video0.jpeg',
      '/720/video1.jpeg',
    ]);
    expect(playlist.segments.first.sequence, 4);
    expect(playlist.segments.first.duration, 4);
    expect(playlist.segments.first.key, isNull);
    expect(playlist.segments.last.sequence, 5);
    expect(playlist.segments.last.key?.uri.path, '/720/key.bin');
    expect(playlist.segments.last.key?.iv?.last, 0x2a);
  });

  test('byte ranges keep offset and the following piece continues', () {
    const body = '''
#EXTM3U
#EXT-X-MAP:URI="movie.mp4",BYTERANGE="10@0"
#EXTINF:4.0,
#EXT-X-BYTERANGE:6@10
movie.mp4
#EXTINF:4.0,
#EXT-X-BYTERANGE:4
movie.mp4
''';
    final playlist = parseHlsPlaylist(
      body,
      Uri.parse('https://cdn.example/video.m3u8'),
    );
    expect(playlist.mapRange?.offset, 0);
    expect(playlist.mapRange?.length, 10);
    expect(playlist.segments.first.range?.offset, 10);
    expect(playlist.segments.first.range?.length, 6);
    expect(playlist.segments.last.range?.offset, 16);
    expect(playlist.segments.last.range?.length, 4);
  });

  test('a master keeps the audio playlist for the best video', () {
    const body = '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aac",NAME="audio",DEFAULT=YES,URI="audio.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=100,RESOLUTION=256x144,AUDIO="aac"
144/video.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=800,RESOLUTION=1280x720,AUDIO="aac"
720/video.m3u8
''';
    final playlist = parseHlsPlaylist(
      body,
      Uri.parse('https://cdn.example/master.m3u8'),
    );
    expect(playlist.bestVariant.uri.path, '/720/video.m3u8');
    expect(playlist.bestVariant.audio?.path, '/audio.m3u8');
  });

  test('byte ranges of one file are saved from that file', () async {
    final movie = Uint8List.fromList([
      0x00,
      0x00,
      0x00,
      0x18,
      0x66,
      0x74,
      0x79,
      0x70,
      0x69,
      0x73,
      0x6f,
      0x35,
      10,
      11,
      12,
      13,
      14,
      15,
      16,
      17,
      18,
      19,
    ]);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.uri.path.endsWith('/video.m3u8')) {
        request.response.write(
          '#EXTM3U\n'
          '#EXT-X-MAP:URI="movie.mp4",BYTERANGE="8@4"\n'
          '#EXTINF:4.0,\n'
          '#EXT-X-BYTERANGE:10@10\n'
          'movie.mp4\n',
        );
      } else if (request.uri.path.endsWith('/movie.mp4')) {
        request.response.add(movie);
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });

    final directory = await Directory.systemTemp.createTemp('hls_range');
    addTearDown(() => directory.delete(recursive: true));
    final saver = StreamSaver(dio: Dio(), workDirectory: () async => directory);
    final file = await saver.fetch(
      stream: FoundStream(
        url: 'http://${server.address.host}:${server.port}/video.m3u8',
        label: 'คุณภาพสูงสุด',
        playlist: true,
      ),
      referer: 'https://m.vkvideo.ru/video-222622962_456239728',
      cookie: null,
      cancelToken: CancelToken(),
      onProgress: (_) {},
    );

    expect(await file.readAsBytes(), movie);
  });

  test('jpeg prefix is removed when transport packets follow it', () {
    final raw = Uint8List(4 + 188 + 1);
    raw[0] = 0xff;
    raw[1] = 0xd8;
    raw[4] = 0x47;
    raw[4 + 188] = 0x47;
    final payload = mediaPayload(raw);
    expect(payload.first, 0x47);
    expect(payload.length, 189);
  });

  test('aes segment round trip removes padding', () {
    final key = Uint8List.fromList(
      List<int>.generate(16, (index) => index + 1),
    );
    final iv = Uint8List(16)..[15] = 7;
    final plain = Uint8List.fromList([0x47, 1, 2, 3, 4, 5]);
    final encrypted = _encrypt(plain, key, iv);
    final decoded = decryptAes128Cbc(data: encrypted, key: key, iv: iv);
    expect(decoded, plain);
  });

  test('playlist segments are joined in order', () async {
    final first = List<int>.generate(20, (index) => index);
    final second = List<int>.generate(10, (index) => 50 + index);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final path = request.uri.path;
      if (path.endsWith('/master.m3u8')) {
        request.response.write(
          '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=100,RESOLUTION=640x360\nlow.m3u8\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=200,RESOLUTION=1280x720\nhigh.m3u8\n',
        );
      } else if (path.endsWith('/high.m3u8')) {
        request.response.write(
          '#EXTM3U\n#EXTINF:1,\na.ts\n#EXTINF:1,\nb.ts\n#EXT-X-ENDLIST\n',
        );
      } else if (path.endsWith('/a.ts')) {
        request.response.add(first);
      } else if (path.endsWith('/b.ts')) {
        request.response.add(second);
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });

    final directory = await Directory.systemTemp.createTemp('hls_join');
    addTearDown(() => directory.delete(recursive: true));
    final saver = StreamSaver(dio: Dio(), workDirectory: () async => directory);
    final file = await saver.fetch(
      stream: FoundStream(
        url: 'http://${server.address.host}:${server.port}/master.m3u8',
        label: 'คุณภาพสูงสุด',
        playlist: true,
      ),
      referer: 'https://example.com/watch',
      cookie: null,
      cancelToken: CancelToken(),
      onProgress: (_) {},
    );

    expect(await file.readAsBytes(), [...first, ...second]);
  });

  test('a video file marked as a stream is saved as that file', () async {
    final movie = Uint8List.fromList([
      0x00, 0x00, 0x00, 0x18, // box size
      0x66, 0x74, 0x79, 0x70, // ftyp
      0x69, 0x73, 0x6f, 0x35, // iso5
      0x61, 0x76, 0x63, 0x31, // avc1
    ]);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.add(movie);
      await request.response.close();
    });

    final directory = await Directory.systemTemp.createTemp('hls_mp4');
    addTearDown(() => directory.delete(recursive: true));
    final saver = StreamSaver(dio: Dio(), workDirectory: () async => directory);
    final file = await saver.fetch(
      stream: FoundStream(
        url: 'http://${server.address.host}:${server.port}/type/2/ondemand',
        label: 'สตรีม',
        playlist: true,
      ),
      referer: 'https://m.vkvideo.ru/video-221115151_456241127',
      cookie: null,
      cancelToken: CancelToken(),
      onProgress: (_) {},
    );

    expect(await file.readAsBytes(), movie);
  });

  test('binary playlist text does not throw', () {
    expect(
      () => parseHlsPlaylist(
        r'$ftypiso5avc1iso5dsmsmsixdash:freeIsoMedia',
        Uri.parse('https://cdn.example/stream'),
      ),
      returnsNormally,
    );
  });
}

Uint8List _encrypt(Uint8List plain, Uint8List key, Uint8List iv) {
  final pad = 16 - (plain.length % 16);
  final input = Uint8List(plain.length + pad);
  input.setRange(0, plain.length, plain);
  for (var index = plain.length; index < input.length; index++) {
    input[index] = pad;
  }
  final cipher = CBCBlockCipher(AESEngine())
    ..init(true, ParametersWithIV(KeyParameter(key), iv));
  final output = Uint8List(input.length);
  for (var offset = 0; offset < input.length; offset += 16) {
    cipher.processBlock(input, offset, output, offset);
  }
  return output;
}
