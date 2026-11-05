import 'package:flutter_test/flutter_test.dart';
import 'package:loading/features/browser/model/found_stream.dart';

void main() {
  test('fragments and previews are not downloadable streams', () {
    expect(foundStreamFromUrl('https://vkvd.okcdn.ru/id/1/00012.mp4'), isNull);
    expect(foundStreamFromUrl('https://vkvd.okcdn.ru/id/1/init.mp4'), isNull);
    expect(foundStreamFromUrl('https://vkvd.okcdn.ru/id/1/seg-3.mp4'), isNull);
    expect(
      foundStreamFromUrl('https://vkvd.okcdn.ru/id/1/preview.mp4'),
      isNull,
    );
    expect(
      foundStreamFromUrl('https://vkvd.okcdn.ru/id/1/clip.mp4?preview=1'),
      isNull,
    );
  });

  test('the opened vk file stays available to download', () {
    const page = 'https://m.vkvideo.ru/video-221115151_456241127';
    final main = foundStreamFromUrl(
      'https://vkvd.okcdn.ru/video/456241127.mp4',
    );
    final other = foundStreamFromUrl(
      'https://vkvd.okcdn.ru/video/999999999.mp4',
    );
    final playlist = foundStreamFromUrl(
      'https://vkvd.okcdn.ru/expires/1/type/2/id/456241127/ondemand',
    );
    expect(main, isNotNull);
    expect(playlist, isNotNull);
    expect(playlist!.playlist, isTrue);
    var streams = addFoundStream(const [], main!, page: page);
    streams = addFoundStream(streams, other!, page: page);
    streams = addFoundStream(streams, playlist, page: page);
    expect(streams.map((stream) => stream.url), [playlist.url, main.url]);
  });

  test('a vk page keeps the opened video master and drops the rest', () {
    const page = 'https://m.vkvideo.ru/video-221115151_456241127';
    const urls = [
      'https://vkvd.okcdn.ru/id/456241127/ondemand/720/index.m3u8',
      'https://vkvd.okcdn.ru/id/456241127/ondemand/1080/index.m3u8',
      'https://vkvd.okcdn.ru/id/456241127/ondemand/00001.mp4',
      'https://vkvd.okcdn.ru/other/preview.mp4',
      'https://vkvd.okcdn.ru/id/999/ondemand/playlist.m3u8',
      'https://vkvd.okcdn.ru/id/456241127/ondemand/playlist.m3u8',
    ];
    var streams = const <FoundStream>[];
    for (final url in urls) {
      final stream = foundStreamFromUrl(url);
      if (stream == null) continue;
      streams = addFoundStream(streams, stream, page: page);
    }
    expect(streams.map((stream) => stream.url), [
      'https://vkvd.okcdn.ru/id/456241127/ondemand/playlist.m3u8',
    ]);
    expect(streams.single.label, 'คุณภาพสูงสุด');
  });

  test('vk dash byte ranges are the whole video, with a separate audio track', () {
    const page = 'https://m.vkvideo.ru/video-221115151_456241127';
    final header = foundStreamFromUrl(
      'https://vk6-14.vkuser.net/?expires=1&type=2&sig=abc&ct=11&id=99&bytes=0-1407',
    );
    final high = foundStreamFromUrl(
      'https://vk6-14.vkuser.net/?expires=1&type=3&sig=def&ct=11&id=99&bytes=900-1411',
    );
    final audio = foundStreamFromUrl(
      'https://vk6-14.vkuser.net/?expires=1&type=3&sig=ghi&ct=12&id=99&bytes=0-836',
    );
    final other = foundStreamFromUrl(
      'https://vk6-14.vkuser.net/?expires=1&type=3&sig=zzz&ct=11&id=100&bytes=0-100',
    );
    expect(header, isNotNull);
    expect(header!.playlist, isFalse);
    expect(header.audioOnly, isFalse);
    expect(header.url.contains('bytes='), isFalse);
    expect(header.url.contains('sig=abc'), isTrue);
    expect(audio!.audioOnly, isTrue);
    expect(audio.url.contains('bytes='), isFalse);
    expect(high!.identity, audio.identity);
    var streams = addFoundStream(const [], header, page: page);
    streams = addFoundStream(streams, high, page: page);
    streams = addFoundStream(streams, other!, page: page);
    expect(
      streams.map((stream) => stream.url),
      unorderedEquals([high.url, header.url]),
    );
  });

  test('a stream caption includes the file size', () {
    const file = FoundStream(
      url: 'https://cdn.example/video.mp4',
      label: '720p',
      playlist: false,
      bytes: 12 * 1024 * 1024,
    );
    const playlist = FoundStream(
      url: 'https://cdn.example/playlist.m3u8',
      label: 'คุณภาพสูงสุด',
      playlist: true,
      bytes: 48 * 1024 * 1024,
    );
    expect(file.caption, '720p · 12.0 MB');
    expect(playlist.caption, 'คุณภาพสูงสุด · ประมาณ 48.0 MB');
  });
}
