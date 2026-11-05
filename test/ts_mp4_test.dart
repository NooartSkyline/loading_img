import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loading/core/app_exception.dart';
import 'package:loading/features/browser/data/stream_saver.dart';
import 'package:loading/features/browser/data/ts_mp4.dart';
import 'package:loading/features/browser/model/found_stream.dart';

void main() {
  test('baseline ts with aac becomes an mp4', () async {
    final ts = _program(_baselineSps(), withAudio: true, dts: true);
    final directory = await Directory.systemTemp.createTemp('ts_mp4');
    addTearDown(() => directory.delete(recursive: true));
    final input = File('${directory.path}/in.ts');
    final output = File('${directory.path}/out.mp4');
    await input.writeAsBytes(ts);
    await remuxTsFile(input.path, output.path);
    final bytes = await output.readAsBytes();

    expect(String.fromCharCodes(bytes.sublist(4, 8)), 'ftyp');
    expect(_hasBox(bytes, 'moov'), isTrue);
    expect(_hasBox(bytes, 'mdat'), isTrue);
    expect(_hasBox(bytes, 'avcC'), isTrue);
    expect(_hasBox(bytes, 'mp4a'), isTrue);
    expect(_hasBox(bytes, 'ctts'), isTrue);
    expect(_trackSize(bytes), (320, 240));
    expect(_boxU32(bytes, 'mvhd', 20), 6000);

    final timed = <int>[];
    for (var index = 0; index < ts.length; index += 188) {
      timed.addAll([0, 0, 0, 0, ...ts.sublist(index, index + 188)]);
    }
    await input.writeAsBytes(timed);
    await remuxTsFile(input.path, output.path);
    expect(_trackSize(await output.readAsBytes()), (320, 240));
  });

  test('high profile sps uses crop for 1920x1080', () async {
    final ts = _program(_highSps(), withAudio: false, dts: false);
    final directory = await Directory.systemTemp.createTemp('ts_mp4_high');
    addTearDown(() => directory.delete(recursive: true));
    final input = File('${directory.path}/in.ts');
    final output = File('${directory.path}/out.mp4');
    await input.writeAsBytes(ts);
    await remuxTsFile(input.path, output.path);
    expect(_trackSize(await output.readAsBytes()), (1920, 1080));
  });

  test('a stream without h264 is rejected', () async {
    final directory = await Directory.systemTemp.createTemp('ts_mp4_bad');
    addTearDown(() => directory.delete(recursive: true));
    final input = File('${directory.path}/in.ts');
    final packet = List<int>.filled(188, 0xFF);
    packet[0] = 0x47;
    await input.writeAsBytes([...packet, ...packet]);
    expect(
      () => remuxTsFile(input.path, '${directory.path}/out.mp4'),
      throwsA(
        isA<AppException>().having((error) => error.message, 'message', contains('H.264')),
      ),
    );
  });

  test('playlist of ts segments is saved as mp4', () async {
    final ts = _program(_baselineSps(), withAudio: false, dts: false);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.uri.path.endsWith('.m3u8')) {
        request.response.write('#EXTM3U\n#EXTINF:1,\nseg.ts\n#EXT-X-ENDLIST\n');
      } else {
        request.response.add(ts);
      }
      await request.response.close();
    });
    final directory = await Directory.systemTemp.createTemp('ts_mp4_hls');
    addTearDown(() => directory.delete(recursive: true));
    final file = await StreamSaver(dio: Dio(), workDirectory: () async => directory).fetch(
      stream: FoundStream(
        url: 'http://${server.address.host}:${server.port}/index.m3u8',
        label: 'สตรีม',
        playlist: true,
      ),
      referer: 'https://example.com/watch',
      cookie: null,
      cancelToken: CancelToken(),
      onProgress: (_) {},
    );
    final bytes = await file.readAsBytes();
    expect(file.path, endsWith('.mp4'));
    expect(String.fromCharCodes(bytes.sublist(4, 8)), 'ftyp');
    expect(_trackSize(bytes), (320, 240));
  });

  test('a ts playlist that is not h264 reports that', () async {
    final packet = List<int>.filled(188, 0xFF);
    packet[0] = 0x47;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.uri.path.endsWith('.m3u8')) {
        request.response.write('#EXTM3U\n#EXTINF:1,\nseg.ts\n#EXT-X-ENDLIST\n');
      } else {
        request.response.add([...packet, ...packet]);
      }
      await request.response.close();
    });
    final directory = await Directory.systemTemp.createTemp('ts_mp4_bad_hls');
    addTearDown(() => directory.delete(recursive: true));
    expect(
      () => StreamSaver(dio: Dio(), workDirectory: () async => directory).fetch(
        stream: FoundStream(
          url: 'http://${server.address.host}:${server.port}/index.m3u8',
          label: 'สตรีม',
          playlist: true,
        ),
        referer: 'https://example.com/watch',
        cookie: null,
        cancelToken: CancelToken(),
        onProgress: (_) {},
      ),
      throwsA(
        isA<AppException>().having((error) => error.message, 'message', contains('H.264')),
      ),
    );
  });
}

Uint8List _baselineSps() {
  final bits = _Bits();
  bits.u(8, 66);
  bits.u(8, 0);
  bits.u(8, 30);
  bits.ue(0);
  bits.ue(0);
  bits.ue(0);
  bits.ue(0);
  bits.ue(1);
  bits.u(1, 0);
  bits.ue(19);
  bits.ue(14);
  bits.u(1, 1);
  bits.u(1, 1);
  bits.u(1, 0);
  return Uint8List.fromList([0x67, ...bits.bytes()]);
}

Uint8List _highSps() {
  final bits = _Bits();
  bits.u(8, 100);
  bits.u(8, 0);
  bits.u(8, 40);
  bits.ue(0);
  bits.ue(1);
  bits.ue(0);
  bits.ue(0);
  bits.u(1, 0);
  bits.u(1, 0);
  bits.ue(0);
  bits.ue(0);
  bits.ue(0);
  bits.ue(1);
  bits.u(1, 0);
  bits.ue(119);
  bits.ue(67);
  bits.u(1, 1);
  bits.u(1, 1);
  bits.u(1, 1);
  bits.ue(0);
  bits.ue(0);
  bits.ue(0);
  bits.ue(4);
  return Uint8List.fromList([0x67, ...bits.bytes()]);
}

List<int> _program(Uint8List sps, {required bool withAudio, required bool dts}) {
  final frame = [
    ..._annex([
      Uint8List.fromList([0x09, 0x10]),
      sps,
      Uint8List.fromList([0x68, 0xCE, 0x38, 0x80]),
      Uint8List.fromList([0x65, 0x88, 0x84, 0x21]),
    ]),
    ...List<int>.filled(420, 0x11),
  ];
  final second = _annex([
    Uint8List.fromList([0x09, 0x10]),
    Uint8List.fromList([0x41, 0x88, 0x84, 0x21]),
  ]);
  final packets = <int>[
    ..._wrap(0, _pat()),
    ..._wrap(0x100, _pmt(withAudio: withAudio)),
    ..._wrap(0x101, _pes(0xE0, frame, pts: dts ? 0 : 9000, dts: dts ? 0 : null)),
  ];
  if (dts) {
    packets.addAll(_wrap(0x101, _pes(0xE0, second, pts: 6000, dts: 3000)));
  }
  if (withAudio) {
    packets.addAll(_wrap(0x102, _pes(0xC0, _adts(), pts: 0)));
  }
  return packets;
}

List<int> _annex(List<Uint8List> nals) {
  final out = <int>[];
  for (final nal in nals) {
    out.addAll([0, 0, 0, 1, ...nal]);
  }
  return out;
}

List<int> _pat() {
  return [
    0x00,
    0x00, 0xB0, 0x0D,
    0x00, 0x01,
    0xC1,
    0x00, 0x00,
    0x00, 0x01,
    0xE1, 0x00,
    0, 0, 0, 0,
  ];
}

List<int> _pmt({required bool withAudio}) {
  final streams = <int>[0x1B, 0xE1, 0x01, 0xF0, 0x00];
  if (withAudio) streams.addAll([0x0F, 0xE1, 0x02, 0xF0, 0x00]);
  final length = 13 + streams.length;
  return [
    0x00,
    0x02,
    0xB0 | ((length >> 8) & 0x0F),
    length & 0xFF,
    0x00, 0x01,
    0xC1,
    0x00, 0x00,
    0xE1, 0x01,
    0xF0, 0x00,
    ...streams,
    0, 0, 0, 0,
  ];
}

List<int> _pes(int streamId, List<int> payload, {required int pts, int? dts}) {
  final header = <int>[..._timestamp(pts, dts == null ? 0x2 : 0x3)];
  if (dts != null) header.addAll(_timestamp(dts, 0x1));
  final after = 3 + header.length + payload.length;
  final length = after > 0xFFFF ? 0 : after;
  return [
    0x00, 0x00, 0x01, streamId,
    (length >> 8) & 0xFF, length & 0xFF,
    0x80,
    dts == null ? 0x80 : 0xC0,
    header.length,
    ...header,
    ...payload,
  ];
}

List<int> _timestamp(int value, int prefix) {
  final time = value & 0x1ffffffff;
  return [
    (prefix << 4) | (((time >> 30) & 7) << 1) | 1,
    (time >> 22) & 0xFF,
    (((time >> 15) & 0x7F) << 1) | 1,
    (time >> 7) & 0xFF,
    ((time & 0x7F) << 1) | 1,
  ];
}

List<int> _adts() {
  return [0xFF, 0xF1, 0x50, 0x80, 0x01, 0x7F, 0xFC, 0x21, 0x10, 0x04, 0x60];
}

List<int> _wrap(int pid, List<int> data) {
  final out = <int>[];
  var offset = 0;
  var continuity = 0;
  var start = true;
  while (offset < data.length) {
    final take = data.length - offset > 184 ? 184 : data.length - offset;
    out.addAll(_packet(pid, start, continuity, data.sublist(offset, offset + take)));
    offset += take;
    continuity = (continuity + 1) & 0x0F;
    start = false;
  }
  return out;
}

List<int> _packet(int pid, bool start, int continuity, List<int> payload) {
  final bytes = List<int>.filled(188, 0xFF);
  bytes[0] = 0x47;
  bytes[1] = (start ? 0x40 : 0) | ((pid >> 8) & 0x1F);
  bytes[2] = pid & 0xFF;
  if (payload.length == 184) {
    bytes[3] = 0x10 | (continuity & 0x0F);
    for (var i = 0; i < payload.length; i++) {
      bytes[4 + i] = payload[i];
    }
    return bytes;
  }
  final adaptLength = 183 - payload.length;
  bytes[3] = 0x30 | (continuity & 0x0F);
  bytes[4] = adaptLength;
  if (adaptLength > 0) bytes[5] = 0;
  final cursor = 5 + adaptLength;
  for (var i = 0; i < payload.length; i++) {
    bytes[cursor + i] = payload[i];
  }
  return bytes;
}

bool _hasBox(Uint8List bytes, String type) {
  final needle = type.codeUnits;
  for (var i = 0; i <= bytes.length - 4; i++) {
    if (bytes[i] == needle[0] && bytes[i + 1] == needle[1] && bytes[i + 2] == needle[2] && bytes[i + 3] == needle[3]) {
      return true;
    }
  }
  return false;
}

int _boxU32(Uint8List bytes, String type, int offset) {
  final needle = type.codeUnits;
  for (var i = 0; i <= bytes.length - 4 - offset; i++) {
    if (bytes[i] == needle[0] && bytes[i + 1] == needle[1] && bytes[i + 2] == needle[2] && bytes[i + 3] == needle[3]) {
      return _be(bytes, i + offset);
    }
  }
  fail('missing $type');
}

(int, int) _trackSize(Uint8List bytes) {
  final index = _indexOf(bytes, 'tkhd');
  final size = _be(bytes, index - 4);
  return (_be(bytes, index - 4 + size - 8) >> 16, _be(bytes, index - 4 + size - 4) >> 16);
}

int _indexOf(Uint8List bytes, String type) {
  final needle = type.codeUnits;
  for (var i = 4; i <= bytes.length - 4; i++) {
    if (bytes[i] == needle[0] && bytes[i + 1] == needle[1] && bytes[i + 2] == needle[2] && bytes[i + 3] == needle[3]) {
      return i;
    }
  }
  fail('missing $type');
}

int _be(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
}

class _Bits {
  final _bits = <int>[];

  void bit(int value) => _bits.add(value & 1);

  void u(int count, int value) {
    for (var shift = count - 1; shift >= 0; shift--) {
      bit((value >> shift) & 1);
    }
  }

  void ue(int value) {
    if (value == 0) {
      bit(1);
      return;
    }
    final zeros = (value + 1).bitLength - 1;
    for (var i = 0; i < zeros; i++) {
      bit(0);
    }
    bit(1);
    u(zeros, value - ((1 << zeros) - 1));
  }

  Uint8List bytes() {
    while (_bits.length % 8 != 0) {
      bit(0);
    }
    final out = Uint8List(_bits.length ~/ 8);
    for (var i = 0; i < _bits.length; i++) {
      if (_bits[i] == 1) out[i >> 3] |= 1 << (7 - (i & 7));
    }
    return out;
  }
}
