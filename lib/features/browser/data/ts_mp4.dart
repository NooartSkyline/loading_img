import 'dart:io';
import 'dart:typed_data';

import 'package:loading/core/app_exception.dart';

/// แปลง MPEG-TS ที่เป็น H.264 (และ AAC ถ้ามี) เป็น mp4 ที่คลังภาพเปิดได้
Future<void> remuxTsFile(String inputPath, String outputPath) async {
  final input = await File(inputPath).open();
  final output = await File(outputPath).open(mode: FileMode.write);
  try {
    final demux = _TsDemux();
    final length = await input.length();
    var pending = Uint8List(0);
    var packetSize = 0;
    var read = 0;
    while (read < length) {
      final chunk = await input.read(1024 * 1024);
      if (chunk.isEmpty) break;
      read += chunk.length;
      final data = Uint8List(pending.length + chunk.length);
      data.setRange(0, pending.length, pending);
      data.setRange(pending.length, data.length, chunk);
      var offset = 0;
      if (packetSize == 0) packetSize = _packetSize(data);
      while (offset + packetSize <= data.length) {
        final start = packetSize == 192 ? offset + 4 : offset;
        demux.addPacket(data, start);
        offset += packetSize;
      }
      pending = Uint8List.sublistView(data, offset);
    }
    demux.finish();
    if (demux.hevc && demux.videoSamples.isEmpty) {
      throw const AppException(
        'สตรีมนี้เป็น HEVC คลังภาพจึงรับไฟล์ที่ต่อได้ไม่ได้',
      );
    }
    if (demux.videoSamples.isEmpty || demux.sps == null || demux.pps == null) {
      throw const AppException(
        'สตรีมนี้ไม่ใช่ H.264 คลังภาพจึงรับไฟล์ที่ต่อได้ไม่ได้',
      );
    }
    await _writeMp4(output, demux);
  } finally {
    await input.close();
    await output.close();
  }
}

int _packetSize(Uint8List data) {
  if (data.length > 188 && data[0] == 0x47 && data[188] == 0x47) return 188;
  if (data.length > 192 && data[4] == 0x47 && data[196] == 0x47) return 192;
  if (data.isNotEmpty && data[0] == 0x47) return 188;
  throw const AppException('ไฟล์สตรีมที่ต่อได้ไม่ใช่ MPEG-TS');
}

class _TsDemux {
  final _pes = <int, _PesBuilder>{};
  final videoSamples = <_Sample>[];
  final audioSamples = <_Sample>[];
  Uint8List? sps;
  Uint8List? pps;
  int? _videoPid;
  int? _audioPid;
  var hevc = false;
  int _audioRate = 44100;
  int _audioObjectType = 2;
  int _audioChannels = 2;
  _AuBuilder? _videoAu;

  int get audioRate => _audioRate;
  int get audioObjectType => _audioObjectType;
  int get audioChannels => _audioChannels;

  void addPacket(Uint8List data, int offset) {
    if (data[offset] != 0x47) return;
    final pid = ((data[offset + 1] & 0x1F) << 8) | data[offset + 2];
    final start = (data[offset + 1] & 0x40) != 0;
    final adapt = (data[offset + 3] >> 4) & 0x03;
    var cursor = offset + 4;
    if (adapt == 2 || adapt == 3) {
      if (cursor >= offset + 188) return;
      final adaptLength = data[cursor];
      cursor += 1 + adaptLength;
    }
    if (adapt == 2 || cursor < offset + 4 || cursor >= offset + 188) return;
    final payload = Uint8List.sublistView(data, cursor, offset + 188);
    if (pid == 0) {
      _parsePat(payload, start);
      return;
    }
    if (pid == _pmtPid || pid == 0x1FFF) {
      if (pid == _pmtPid) _parsePmt(payload, start);
      return;
    }
    if (start &&
        payload.length >= 4 &&
        payload[0] == 0 &&
        payload[1] == 0 &&
        payload[2] == 1) {
      final streamId = payload[3];
      if (_videoPid == null && streamId >= 0xE0 && streamId <= 0xEF)
        _videoPid = pid;
      if (_audioPid == null && streamId >= 0xC0 && streamId <= 0xDF)
        _audioPid = pid;
    }
    if (pid != _videoPid && pid != _audioPid) return;
    final builder = _pes.putIfAbsent(pid, _PesBuilder.new);
    if (start && builder.started) _flushPes(pid, builder.take());
    builder.add(payload, start);
  }

  void finish() {
    for (final entry in _pes.entries) {
      if (entry.value.started) _flushPes(entry.key, entry.value.take());
    }
    final au = _videoAu;
    if (au != null && au.nals.isNotEmpty) videoSamples.add(au.toSample());
    _videoAu = null;
  }

  int? _pmtPid;
  final _psi = <int, List<int>>{};

  void _parsePat(Uint8List payload, bool start) {
    final section = _section(0, payload, start);
    if (section == null || section.length < 8) return;
    final length = ((section[1] & 0x0F) << 8) | section[2];
    var index = 8;
    final end = 3 + length - 4;
    while (index + 4 <= section.length && index < end) {
      final program = (section[index] << 8) | section[index + 1];
      final pid = ((section[index + 2] & 0x1F) << 8) | section[index + 3];
      if (program != 0) {
        _pmtPid = pid;
        return;
      }
      index += 4;
    }
  }

  void _parsePmt(Uint8List payload, bool start) {
    final section = _section(_pmtPid ?? -1, payload, start);
    if (section == null || section.length < 12 || section[0] != 2) return;
    final length = ((section[1] & 0x0F) << 8) | section[2];
    final infoLength = ((section[10] & 0x0F) << 8) | section[11];
    var index = 12 + infoLength;
    final end = 3 + length - 4;
    while (index + 5 <= section.length && index < end) {
      final streamType = section[index];
      final pid = ((section[index + 1] & 0x1F) << 8) | section[index + 2];
      final esLength = ((section[index + 3] & 0x0F) << 8) | section[index + 4];
      if (streamType == 0x24) hevc = true;
      if (streamType == 0x1B && _videoPid == null) _videoPid = pid;
      if ((streamType == 0x0F || streamType == 0x11) && _audioPid == null)
        _audioPid = pid;
      index += 5 + esLength;
    }
  }

  Uint8List? _section(int pid, Uint8List payload, bool start) {
    if (payload.isEmpty) return null;
    if (start) {
      final pointer = payload[0];
      final from = 1 + pointer;
      if (from > payload.length) return null;
      _psi[pid] = payload.sublist(from).toList();
    } else {
      _psi.putIfAbsent(pid, () => <int>[]).addAll(payload);
    }
    final buffer = _psi[pid];
    if (buffer == null || buffer.length < 3) return null;
    final length = ((buffer[1] & 0x0F) << 8) | buffer[2];
    final total = 3 + length;
    if (buffer.length < total) return null;
    return Uint8List.fromList(buffer.sublist(0, total));
  }

  void _flushPes(int pid, _Pes pes) {
    if (pes.payload.isEmpty) return;
    if (pid == _videoPid || (_videoPid == null && pes.streamId == 0xE0)) {
      _videoPid ??= pid;
      _consumeVideo(pes);
      return;
    }
    if (pid == _audioPid || (_audioPid == null && pes.streamId == 0xC0)) {
      _audioPid ??= pid;
      _consumeAudio(pes);
    }
  }

  void _consumeVideo(_Pes pes) {
    for (final nal in _annexB(pes.payload)) {
      if (nal.isEmpty) continue;
      final type = nal[0] & 0x1F;
      if (type == 7) {
        sps ??= Uint8List.fromList(nal);
        continue;
      }
      if (type == 8) {
        pps ??= Uint8List.fromList(nal);
        continue;
      }
      if (type == 9) {
        final current = _videoAu;
        if (current != null && current.nals.isNotEmpty)
          videoSamples.add(current.toSample());
        _videoAu = _AuBuilder(pes.pts, pes.dts);
        continue;
      }
      if (type == 1 || type == 5) {
        final starts = _firstMbIsZero(nal);
        final current = _videoAu;
        if (current != null && current.hasVcl && starts) {
          videoSamples.add(current.toSample());
          _videoAu = _AuBuilder(pes.pts, pes.dts);
        }
        _videoAu ??= _AuBuilder(pes.pts, pes.dts);
      }
      _videoAu ??= _AuBuilder(pes.pts, pes.dts);
      if (type == 5) _videoAu!.sync = true;
      if (type != 9 && type != 7 && type != 8) _videoAu!.nals.add(nal);
      if (type == 1 || type == 5) _videoAu!.hasVcl = true;
    }
  }

  void _consumeAudio(_Pes pes) {
    final frames = _adtsFrames(pes.payload);
    if (frames.isEmpty) return;
    var pts = pes.pts;
    for (final frame in frames) {
      audioSamples.add(_Sample(frame.bytes, pts, dts: pts, sync: true));
      final current = pts;
      if (current != null)
        pts = (current + (1024 * 90000) ~/ _audioRate) & 0x1ffffffff;
    }
  }

  List<Uint8List> _annexB(Uint8List data) {
    final starts = <int>[];
    var index = 0;
    while (index + 2 < data.length) {
      if (data[index] == 0 && data[index + 1] == 0) {
        if (index + 3 < data.length &&
            data[index + 2] == 0 &&
            data[index + 3] == 1) {
          starts.add(index + 4);
          index += 4;
          continue;
        }
        if (data[index + 2] == 1) {
          starts.add(index + 3);
          index += 3;
          continue;
        }
      }
      index += 1;
    }
    final nals = <Uint8List>[];
    for (var i = 0; i < starts.length; i++) {
      final from = starts[i];
      final to = i + 1 < starts.length
          ? _startCodeStart(data, starts[i + 1])
          : data.length;
      if (to > from) nals.add(Uint8List.sublistView(data, from, to));
    }
    return nals;
  }

  int _startCodeStart(Uint8List data, int nalStart) {
    if (nalStart >= 4 &&
        data[nalStart - 4] == 0 &&
        data[nalStart - 3] == 0 &&
        data[nalStart - 2] == 0 &&
        data[nalStart - 1] == 1) {
      return nalStart - 4;
    }
    return nalStart - 3;
  }

  bool _firstMbIsZero(Uint8List nal) {
    try {
      return _BitReader(_rbsp(nal.sublist(1))).ue() == 0;
    } on Object {
      return true;
    }
  }

  List<_Adts> _adtsFrames(Uint8List data) {
    final frames = <_Adts>[];
    var index = 0;
    while (index + 7 < data.length) {
      if (data[index] != 0xFF || (data[index + 1] & 0xF0) != 0xF0) {
        index += 1;
        continue;
      }
      final header = (data[index + 1] & 0x01) == 1 ? 7 : 9;
      final length =
          ((data[index + 3] & 0x03) << 11) |
          (data[index + 4] << 3) |
          ((data[index + 5] & 0xE0) >> 5);
      if (length < header || index + length > data.length) break;
      _audioObjectType = ((data[index + 2] >> 6) & 0x03) + 1;
      final rateIndex = (data[index + 2] >> 2) & 0x0F;
      if (rateIndex < _sampleRates.length) _audioRate = _sampleRates[rateIndex];
      _audioChannels =
          ((data[index + 2] & 0x01) << 2) | ((data[index + 3] >> 6) & 0x03);
      frames.add(
        _Adts(Uint8List.sublistView(data, index + header, index + length)),
      );
      index += length;
    }
    return frames;
  }
}

class _PesBuilder {
  final _bytes = BytesBuilder(copy: false);
  var started = false;

  void add(Uint8List data, bool start) {
    if (start) {
      _bytes.clear();
      started = true;
    }
    if (!started) return;
    _bytes.add(data);
  }

  _Pes take() {
    started = false;
    final data = _bytes.toBytes();
    _bytes.clear();
    if (data.length < 6 || data[0] != 0 || data[1] != 0 || data[2] != 1) {
      return _Pes(0, null, null, Uint8List(0));
    }
    final streamId = data[3];
    final flagsOffset = 6;
    if (data.length < flagsOffset + 3)
      return _Pes(streamId, null, null, Uint8List(0));
    final headerLength = data[flagsOffset + 2];
    final payloadFrom = flagsOffset + 3 + headerLength;
    int? pts;
    int? dts;
    final ptsDts = (data[flagsOffset + 1] >> 6) & 0x03;
    if (ptsDts >= 2 && data.length >= flagsOffset + 8) {
      pts = _pts(data, flagsOffset + 3);
      dts = pts;
    }
    if (ptsDts == 3 && data.length >= flagsOffset + 13) {
      dts = _pts(data, flagsOffset + 8);
    }
    if (payloadFrom > data.length)
      return _Pes(streamId, pts, dts, Uint8List(0));
    return _Pes(streamId, pts, dts, Uint8List.sublistView(data, payloadFrom));
  }
}

class _Pes {
  const _Pes(this.streamId, this.pts, this.dts, this.payload);

  final int streamId;
  final int? pts;
  final int? dts;
  final Uint8List payload;
}

class _AuBuilder {
  _AuBuilder(this.pts, this.dts);

  final int? pts;
  final int? dts;
  final nals = <Uint8List>[];
  var hasVcl = false;
  var sync = false;

  _Sample toSample() {
    final body = BytesBuilder(copy: false);
    for (final nal in nals) {
      body.addByte((nal.length >> 24) & 0xFF);
      body.addByte((nal.length >> 16) & 0xFF);
      body.addByte((nal.length >> 8) & 0xFF);
      body.addByte(nal.length & 0xFF);
      body.add(nal);
    }
    return _Sample(body.toBytes(), pts, dts: dts, sync: sync);
  }
}

class _Sample {
  const _Sample(this.bytes, this.pts, {required this.dts, required this.sync});

  final Uint8List bytes;
  final int? pts;
  final int? dts;
  final bool sync;
}

class _Adts {
  const _Adts(this.bytes);

  final Uint8List bytes;
}

const _sampleRates = <int>[
  96000,
  88200,
  64000,
  48000,
  44100,
  32000,
  24000,
  22050,
  16000,
  12000,
  11025,
  8000,
  7350,
];

int _pts(Uint8List data, int offset) {
  final b0 = data[offset];
  final b1 = data[offset + 1];
  final b2 = data[offset + 2];
  final b3 = data[offset + 3];
  final b4 = data[offset + 4];
  return ((b0 & 0x0E) << 29) |
      (b1 << 22) |
      ((b2 & 0xFE) << 14) |
      (b3 << 7) |
      (b4 >> 1);
}

Uint8List _rbsp(Uint8List data) {
  final out = <int>[];
  for (var i = 0; i < data.length; i++) {
    if (i + 2 < data.length &&
        data[i] == 0 &&
        data[i + 1] == 0 &&
        data[i + 2] == 3) {
      out.add(0);
      out.add(0);
      i += 2;
      continue;
    }
    out.add(data[i]);
  }
  return Uint8List.fromList(out);
}

class _Sps {
  const _Sps(this.width, this.height, this.profile, this.compat, this.level);

  final int width;
  final int height;
  final int profile;
  final int compat;
  final int level;
}

_Sps _parseSps(Uint8List nal) {
  final reader = _BitReader(_rbsp(nal.sublist(1)));
  final profile = reader.u(8);
  final compat = reader.u(8);
  final level = reader.u(8);
  reader.ue();
  var chroma = 1;
  if (_highProfile(profile)) {
    chroma = reader.ue();
    if (chroma == 3) reader.u(1);
    reader.ue();
    reader.ue();
    reader.u(1);
    if (reader.u(1) == 1) {
      final count = chroma == 3 ? 12 : 8;
      for (var i = 0; i < count; i++) {
        if (reader.u(1) == 1) _skipScaling(reader, i < 6 ? 16 : 64);
      }
    }
  }
  reader.ue();
  final poc = reader.ue();
  if (poc == 0) {
    reader.ue();
  } else if (poc == 1) {
    reader.u(1);
    reader.se();
    reader.se();
    final cycles = reader.ue();
    for (var i = 0; i < cycles; i++) {
      reader.se();
    }
  }
  reader.ue();
  reader.u(1);
  final widthMbs = reader.ue() + 1;
  final heightUnits = reader.ue() + 1;
  final frameOnly = reader.u(1) == 1;
  if (!frameOnly) reader.u(1);
  reader.u(1);
  var cropLeft = 0;
  var cropRight = 0;
  var cropTop = 0;
  var cropBottom = 0;
  if (reader.u(1) == 1) {
    cropLeft = reader.ue();
    cropRight = reader.ue();
    cropTop = reader.ue();
    cropBottom = reader.ue();
  }
  final unitX = chroma == 1 || chroma == 2 ? 2 : 1;
  final unitY = (chroma == 1 ? 2 : 1) * (frameOnly ? 1 : 2);
  final width = widthMbs * 16 - (cropLeft + cropRight) * unitX;
  final height =
      heightUnits * 16 * (frameOnly ? 1 : 2) - (cropTop + cropBottom) * unitY;
  return _Sps(width, height, profile, compat, level);
}

bool _highProfile(int profile) {
  const ids = {100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135};
  return ids.contains(profile);
}

void _skipScaling(_BitReader reader, int size) {
  var last = 8;
  var next = 8;
  for (var i = 0; i < size; i++) {
    if (next != 0) next = (last + reader.se() + 256) % 256;
    last = next == 0 ? last : next;
  }
}

class _BitReader {
  _BitReader(this.data);

  final Uint8List data;
  int _bit = 0;

  int u(int count) {
    var value = 0;
    for (var i = 0; i < count; i++) {
      final index = _bit >> 3;
      if (index >= data.length)
        throw const AppException('อ่านค่าในวิดีโอไม่ครบ');
      final shift = 7 - (_bit & 7);
      value = (value << 1) | ((data[index] >> shift) & 1);
      _bit += 1;
    }
    return value;
  }

  int ue() {
    var zeros = 0;
    while (u(1) == 0) {
      zeros += 1;
      if (zeros > 31) throw const AppException('อ่านค่าในวิดีโอไม่ครบ');
    }
    if (zeros == 0) return 0;
    return ((1 << zeros) - 1) + u(zeros);
  }

  int se() {
    final value = ue();
    final magnitude = (value + 1) >> 1;
    return (value & 1) == 0 ? -magnitude : magnitude;
  }
}

Future<void> _writeMp4(RandomAccessFile output, _TsDemux demux) async {
  final spsInfo = _parseSps(demux.sps!);
  final ftyp = _ftyp();
  await output.writeFrom(ftyp.data);
  final mdatPos = await output.position();
  await output.writeFrom(Uint8List(8));
  final videoOffsets = <int>[];
  final videoSizes = <int>[];
  for (final sample in demux.videoSamples) {
    videoOffsets.add(await output.position());
    videoSizes.add(sample.bytes.length);
    await output.writeFrom(sample.bytes);
  }
  final audioOffsets = <int>[];
  final audioSizes = <int>[];
  for (final sample in demux.audioSamples) {
    audioOffsets.add(await output.position());
    audioSizes.add(sample.bytes.length);
    await output.writeFrom(sample.bytes);
  }
  final mdatEnd = await output.position();
  await output.setPosition(mdatPos);
  await output.writeFrom(_u32(mdatEnd - mdatPos));
  await output.writeFrom('mdat'.codeUnits);
  await output.setPosition(mdatEnd);
  final videoDurations = _mediaDurations(demux.videoSamples, 90000, 3000);
  final audioDurations = demux.audioSamples.isEmpty
      ? const <int>[]
      : _mediaDurations(demux.audioSamples, demux.audioRate, 1024);
  final videoTicks = videoDurations.fold<int>(0, (sum, item) => sum + item);
  final audioMediaTicks = audioDurations.fold<int>(
    0,
    (sum, item) => sum + item,
  );
  final audioMovieTicks = audioDurations.isEmpty
      ? 0
      : audioMediaTicks * 90000 ~/ demux.audioRate;
  final movieTicks = videoTicks > audioMovieTicks
      ? videoTicks
      : audioMovieTicks;
  if (mdatEnd > 0xFFFFFFFF || mdatEnd - mdatPos > 0xFFFFFFFF) {
    throw const AppException('วิดีโอนี้ใหญ่เกินกว่าจะแปลงเข้าคลังภาพ');
  }
  final moov = _buf();
  _box(moov, 'moov', () {
    _mvhd(moov, movieTicks, demux.audioSamples.isEmpty ? 2 : 3);
    _videoTrack(
      moov,
      demux,
      spsInfo,
      videoDurations,
      videoSizes,
      videoOffsets,
      videoTicks,
    );
    if (demux.audioSamples.isNotEmpty) {
      _audioTrack(
        moov,
        demux,
        audioDurations,
        audioSizes,
        audioOffsets,
        audioMovieTicks,
        audioMediaTicks,
      );
    }
  });
  await output.writeFrom(moov.data);
}

List<int> _mediaDurations(List<_Sample> samples, int timescale, int fallback) {
  final values = <int>[];
  for (var i = 0; i < samples.length; i++) {
    final current = samples[i].dts ?? samples[i].pts;
    final next = i + 1 < samples.length
        ? samples[i + 1].dts ?? samples[i + 1].pts
        : null;
    var delta = fallback;
    if (current != null && next != null) {
      var ticks = next - current;
      if (ticks < 0) ticks += 0x200000000;
      final scaled = ticks * timescale ~/ 90000;
      if (scaled > 0 && scaled <= timescale * 2) delta = scaled;
    } else if (values.isNotEmpty) {
      delta = values.last;
    }
    values.add(delta);
  }
  return values;
}

List<int>? _compositionOffsets(List<_Sample> samples) {
  final offsets = <int>[];
  var used = false;
  for (final sample in samples) {
    final dts = sample.dts ?? sample.pts;
    final pts = sample.pts ?? dts;
    if (dts == null || pts == null) {
      offsets.add(0);
      continue;
    }
    var delta = pts - dts;
    if (delta > 0x7fffffff) delta -= 0x200000000;
    if (delta < -0x80000000) delta += 0x200000000;
    if (delta != 0) used = true;
    offsets.add(delta);
  }
  if (!used) return null;
  return offsets;
}

_Buf _ftyp() {
  final buf = _buf();
  _box(buf, 'ftyp', () {
    buf.ascii('isom');
    buf.u32(0x200);
    buf.ascii('isom');
    buf.ascii('iso2');
    buf.ascii('avc1');
    buf.ascii('mp41');
  });
  return buf;
}

void _mvhd(_Buf buf, int duration, int nextTrack) {
  _box(buf, 'mvhd', () {
    buf.u32(0);
    buf.u32(0);
    buf.u32(0);
    buf.u32(90000);
    buf.u32(duration);
    buf.u32(0x00010000);
    buf.u16(0x0100);
    buf.u16(0);
    buf.u32(0);
    buf.u32(0);
    _matrix(buf);
    for (var i = 0; i < 6; i++) {
      buf.u32(0);
    }
    buf.u32(nextTrack);
  });
}

void _videoTrack(
  _Buf buf,
  _TsDemux demux,
  _Sps sps,
  List<int> durations,
  List<int> sizes,
  List<int> offsets,
  int ticks,
) {
  _box(buf, 'trak', () {
    _tkhd(buf, 1, ticks, sps.width, sps.height, volume: 0);
    _box(buf, 'mdia', () {
      _mdhd(buf, 90000, ticks);
      _hdlr(buf, 'vide', 'VideoHandler');
      _box(buf, 'minf', () {
        _box(buf, 'vmhd', () {
          buf.u32(1);
          buf.u16(0);
          buf.u16(0);
          buf.u16(0);
          buf.u16(0);
        });
        _dinf(buf);
        _box(buf, 'stbl', () {
          _box(buf, 'stsd', () {
            buf.u32(0);
            buf.u32(1);
            _box(buf, 'avc1', () {
              buf.bytes(Uint8List(6));
              buf.u16(1);
              buf.u16(0);
              buf.u16(0);
              buf.u32(0);
              buf.u32(0);
              buf.u32(0);
              buf.u16(sps.width);
              buf.u16(sps.height);
              buf.u32(0x00480000);
              buf.u32(0x00480000);
              buf.u32(0);
              buf.u16(1);
              buf.bytes(Uint8List(32));
              buf.u16(0x0018);
              buf.i16(-1);
              _avcC(buf, demux.sps!, demux.pps!, sps);
            });
          });
          _stts(buf, durations);
          final composition = _compositionOffsets(demux.videoSamples);
          if (composition != null) _ctts(buf, composition);
          _stss(buf, demux.videoSamples);
          _stsc(buf);
          _stsz(buf, sizes);
          _stco(buf, offsets);
        });
      });
    });
  });
}

void _audioTrack(
  _Buf buf,
  _TsDemux demux,
  List<int> durations,
  List<int> sizes,
  List<int> offsets,
  int movieTicks,
  int mediaTicks,
) {
  _box(buf, 'trak', () {
    _tkhd(buf, 2, movieTicks, 0, 0, volume: 0x0100);
    _box(buf, 'mdia', () {
      _mdhd(buf, demux.audioRate, mediaTicks);
      _hdlr(buf, 'soun', 'SoundHandler');
      _box(buf, 'minf', () {
        _box(buf, 'smhd', () {
          buf.u32(0);
          buf.u16(0);
          buf.u16(0);
        });
        _dinf(buf);
        _box(buf, 'stbl', () {
          _box(buf, 'stsd', () {
            buf.u32(0);
            buf.u32(1);
            _box(buf, 'mp4a', () {
              buf.bytes(Uint8List(6));
              buf.u16(1);
              buf.u32(0);
              buf.u32(0);
              buf.u16(demux.audioChannels);
              buf.u16(16);
              buf.u16(0);
              buf.u16(0);
              buf.u32(demux.audioRate << 16);
              _esds(buf, demux);
            });
          });
          _stts(buf, durations);
          _stsc(buf);
          _stsz(buf, sizes);
          _stco(buf, offsets);
        });
      });
    });
  });
}

void _tkhd(
  _Buf buf,
  int id,
  int duration,
  int width,
  int height, {
  required int volume,
}) {
  _box(buf, 'tkhd', () {
    buf.u32(7);
    buf.u32(0);
    buf.u32(0);
    buf.u32(id);
    buf.u32(0);
    buf.u32(duration);
    buf.u32(0);
    buf.u32(0);
    buf.u16(0);
    buf.u16(0);
    buf.u16(volume);
    buf.u16(0);
    _matrix(buf);
    buf.u32(width << 16);
    buf.u32(height << 16);
  });
}

void _mdhd(_Buf buf, int timescale, int duration) {
  _box(buf, 'mdhd', () {
    buf.u32(0);
    buf.u32(0);
    buf.u32(0);
    buf.u32(timescale);
    buf.u32(duration);
    buf.u16(0x55C4);
    buf.u16(0);
  });
}

void _hdlr(_Buf buf, String type, String name) {
  _box(buf, 'hdlr', () {
    buf.u32(0);
    buf.u32(0);
    buf.ascii(type);
    buf.u32(0);
    buf.u32(0);
    buf.u32(0);
    buf.ascii(name);
    buf.u8(0);
  });
}

void _dinf(_Buf buf) {
  _box(buf, 'dinf', () {
    _box(buf, 'dref', () {
      buf.u32(0);
      buf.u32(1);
      _box(buf, 'url ', () => buf.u32(1));
    });
  });
}

void _avcC(_Buf buf, Uint8List sps, Uint8List pps, _Sps info) {
  _box(buf, 'avcC', () {
    buf.u8(1);
    buf.u8(info.profile);
    buf.u8(info.compat);
    buf.u8(info.level);
    buf.u8(0xFF);
    buf.u8(0xE1);
    buf.u16(sps.length);
    buf.bytes(sps);
    buf.u8(1);
    buf.u16(pps.length);
    buf.bytes(pps);
  });
}

void _esds(_Buf buf, _TsDemux demux) {
  final specific = Uint8List(2);
  final value =
      (demux.audioObjectType << 11) |
      (_rateIndex(demux.audioRate) << 7) |
      (demux.audioChannels << 3);
  specific[0] = (value >> 8) & 0xFF;
  specific[1] = value & 0xFF;
  final decoder = _buf();
  decoder.u8(0x40);
  decoder.u8(0x15);
  decoder.u24(0);
  decoder.u32(0);
  decoder.u32(0);
  _desc(decoder, 0x05, specific);
  final es = _buf();
  es.u16(0);
  es.u8(0);
  _desc(es, 0x04, decoder.toBytes());
  _desc(es, 0x06, Uint8List.fromList([0x02]));
  _box(buf, 'esds', () {
    buf.u32(0);
    _desc(buf, 0x03, es.toBytes());
  });
}

int _rateIndex(int rate) {
  final index = _sampleRates.indexOf(rate);
  return index < 0 ? 4 : index;
}

void _desc(_Buf buf, int tag, List<int> body) {
  buf.u8(tag);
  buf.u8(0x80);
  buf.u8(0x80);
  buf.u8(0x80);
  buf.u8(body.length);
  buf.bytes(body);
}

void _ctts(_Buf buf, List<int> offsets) {
  final runs = <List<int>>[];
  for (final offset in offsets) {
    if (runs.isNotEmpty && runs.last[1] == offset) {
      runs.last[0] += 1;
    } else {
      runs.add([1, offset]);
    }
  }
  final negative = offsets.any((offset) => offset < 0);
  _box(buf, 'ctts', () {
    buf.u32(negative ? 0x01000000 : 0);
    buf.u32(runs.length);
    for (final run in runs) {
      buf.u32(run[0]);
      buf.i32(run[1]);
    }
  });
}

void _stts(_Buf buf, List<int> durations) {
  final runs = <List<int>>[];
  for (final duration in durations) {
    if (runs.isNotEmpty && runs.last[1] == duration) {
      runs.last[0] += 1;
    } else {
      runs.add([1, duration]);
    }
  }
  _box(buf, 'stts', () {
    buf.u32(0);
    buf.u32(runs.length);
    for (final run in runs) {
      buf.u32(run[0]);
      buf.u32(run[1]);
    }
  });
}

void _stss(_Buf buf, List<_Sample> samples) {
  final keys = <int>[];
  for (var i = 0; i < samples.length; i++) {
    if (samples[i].sync) keys.add(i + 1);
  }
  if (keys.isEmpty && samples.isNotEmpty) keys.add(1);
  _box(buf, 'stss', () {
    buf.u32(0);
    buf.u32(keys.length);
    for (final key in keys) {
      buf.u32(key);
    }
  });
}

void _stsc(_Buf buf) {
  _box(buf, 'stsc', () {
    buf.u32(0);
    buf.u32(1);
    buf.u32(1);
    buf.u32(1);
    buf.u32(1);
  });
}

void _stsz(_Buf buf, List<int> sizes) {
  _box(buf, 'stsz', () {
    buf.u32(0);
    buf.u32(0);
    buf.u32(sizes.length);
    for (final size in sizes) {
      buf.u32(size);
    }
  });
}

void _stco(_Buf buf, List<int> offsets) {
  _box(buf, 'stco', () {
    buf.u32(0);
    buf.u32(offsets.length);
    for (final offset in offsets) {
      buf.u32(offset);
    }
  });
}

void _matrix(_Buf buf) {
  buf.u32(0x00010000);
  buf.u32(0);
  buf.u32(0);
  buf.u32(0);
  buf.u32(0x00010000);
  buf.u32(0);
  buf.u32(0);
  buf.u32(0);
  buf.u32(0x40000000);
}

void _box(_Buf buf, String type, void Function() write) {
  final start = buf.length;
  buf.u32(0);
  buf.ascii(type);
  write();
  buf.setU32(start, buf.length - start);
}

_Buf _buf() => _Buf();

class _Buf {
  final data = <int>[];

  int get length => data.length;

  void u8(int value) => data.add(value & 0xFF);

  void u16(int value) {
    u8(value >> 8);
    u8(value);
  }

  void u24(int value) {
    u8(value >> 16);
    u8(value >> 8);
    u8(value);
  }

  void u32(int value) {
    u8(value >> 24);
    u8(value >> 16);
    u8(value >> 8);
    u8(value);
  }

  void i16(int value) => u16(value);

  void i32(int value) => u32(value);

  void ascii(String value) => data.addAll(value.codeUnits);

  void bytes(List<int> value) => data.addAll(value);

  void setU32(int offset, int value) {
    data[offset] = (value >> 24) & 0xFF;
    data[offset + 1] = (value >> 16) & 0xFF;
    data[offset + 2] = (value >> 8) & 0xFF;
    data[offset + 3] = value & 0xFF;
  }

  Uint8List toBytes() => Uint8List.fromList(data);
}

Uint8List _u32(int value) {
  return Uint8List.fromList([
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ]);
}
