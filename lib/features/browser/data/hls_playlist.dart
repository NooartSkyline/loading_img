import 'dart:typed_data';

import 'package:loading/core/app_exception.dart';

class HlsVariant {
  const HlsVariant({
    required this.uri,
    required this.bandwidth,
    this.resolution,
    this.audio,
  });

  final Uri uri;
  final int bandwidth;
  final String? resolution;
  final Uri? audio;

  int get rank {
    final size = RegExp(r'(\d+)x(\d+)').firstMatch(resolution ?? '');
    if (size != null) return int.tryParse(size.group(2) ?? '') ?? bandwidth;
    return bandwidth;
  }
}

class HlsKey {
  const HlsKey({required this.uri, this.iv});

  final Uri uri;
  final Uint8List? iv;
}

class HlsByteRange {
  const HlsByteRange(this.offset, this.length);

  final int offset;
  final int length;
}

class HlsSegment {
  const HlsSegment({
    required this.uri,
    required this.sequence,
    this.key,
    this.duration,
    this.range,
  });

  final Uri uri;
  final int sequence;
  final HlsKey? key;
  final double? duration;
  final HlsByteRange? range;
}

class HlsPlaylist {
  const HlsPlaylist({
    required this.variants,
    required this.segments,
    this.mapUri,
    this.mapRange,
  });

  final List<HlsVariant> variants;
  final List<HlsSegment> segments;
  final Uri? mapUri;
  final HlsByteRange? mapRange;

  bool get isMaster => variants.isNotEmpty;

  HlsVariant get bestVariant {
    final items = variants;
    if (items.isEmpty) {
      throw const AppException('ไม่พบความละเอียดในสตรีมนี้');
    }
    var best = items.first;
    for (final item in items.skip(1)) {
      if (item.rank > best.rank) best = item;
    }
    return best;
  }
}

HlsPlaylist parseHlsPlaylist(String body, Uri base) {
  final variants = <HlsVariant>[];
  final segments = <HlsSegment>[];
  int? bandwidth;
  String? resolution;
  var sawInf = false;
  double? pendingDuration;
  HlsKey? currentKey;
  Uri? mapUri;
  HlsByteRange? mapRange;
  var sequence = 0;
  _OpenRange? pendingRange;
  String? audioGroup;
  final audioGroups = <String, Uri>{};
  final rangeEnds = <String, int>{};

  for (final raw in body.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
      sequence = int.tryParse(line.split(':').last.trim()) ?? 0;
      continue;
    }
    if (line.startsWith('#EXT-X-MEDIA:')) {
      _rememberAudio(line, base, audioGroups);
      continue;
    }
    if (line.startsWith('#EXT-X-STREAM-INF:')) {
      bandwidth = _attrInt(line, 'BANDWIDTH');
      resolution = _attr(line, 'RESOLUTION');
      audioGroup = _attr(line, 'AUDIO');
      sawInf = false;
      continue;
    }
    if (line.startsWith('#EXT-X-MAP:')) {
      final uri = _attr(line, 'URI');
      if (uri != null) mapUri = base.resolve(uri);
      mapRange = _quotedRange(_attr(line, 'BYTERANGE'));
      continue;
    }
    if (line.startsWith('#EXT-X-BYTERANGE:')) {
      pendingRange = _openRange(line.split(':').last.trim());
      continue;
    }
    if (line.startsWith('#EXT-X-KEY:')) {
      currentKey = _key(line, base);
      continue;
    }
    if (line.startsWith('#EXTINF:')) {
      final raw = line.substring('#EXTINF:'.length).split(',').first.trim();
      pendingDuration = double.tryParse(raw);
      sawInf = true;
      continue;
    }
    if (line.startsWith('#')) continue;

    final uri = _resolve(base, line);
    if (uri == null) continue;
    if (bandwidth != null || resolution != null) {
      variants.add(
        HlsVariant(
          uri: uri,
          bandwidth: bandwidth ?? 0,
          resolution: resolution,
          audio: audioGroup == null ? null : audioGroups[audioGroup],
        ),
      );
      bandwidth = null;
      resolution = null;
      audioGroup = null;
      continue;
    }
    if (sawInf || variants.isEmpty) {
      segments.add(
        HlsSegment(
          uri: uri,
          sequence: sequence,
          key: currentKey,
          duration: pendingDuration,
          range: _segmentRange(uri, pendingRange, rangeEnds),
        ),
      );
      pendingRange = null;
      sequence += 1;
      sawInf = false;
      pendingDuration = null;
    }
  }

  return HlsPlaylist(
    variants: variants,
    segments: segments,
    mapUri: mapUri,
    mapRange: mapRange,
  );
}

class _OpenRange {
  const _OpenRange(this.length, this.offset);

  final int length;
  final int? offset;
}

void _rememberAudio(String line, Uri base, Map<String, Uri> groups) {
  final type = (_attr(line, 'TYPE') ?? '').toUpperCase();
  if (type != 'AUDIO') return;
  final group = _attr(line, 'GROUP-ID');
  final raw = _attr(line, 'URI');
  if (group == null || raw == null) return;
  final uri = _resolve(base, raw);
  if (uri == null) return;
  final preferred = (_attr(line, 'DEFAULT') ?? '').toUpperCase() == 'YES';
  if (preferred || !groups.containsKey(group)) groups[group] = uri;
}

_OpenRange _openRange(String spec) {
  final match = RegExp(r'^(\d+)(?:@(\d+))?$').firstMatch(spec.trim());
  if (match == null) {
    throw const AppException('สตรีมนี้ระบุช่วงไบต์ไม่ครบ');
  }
  return _OpenRange(
    int.parse(match.group(1)!),
    match.group(2) == null ? null : int.parse(match.group(2)!),
  );
}

HlsByteRange? _quotedRange(String? spec) {
  if (spec == null || spec.isEmpty) return null;
  final open = _openRange(spec);
  if (open.offset == null) {
    throw const AppException('สตรีมนี้ระบุช่วงไบต์ไม่ครบ');
  }
  return HlsByteRange(open.offset!, open.length);
}

HlsByteRange? _segmentRange(
  Uri uri,
  _OpenRange? pending,
  Map<String, int> ends,
) {
  if (pending == null) return null;
  final key = uri.toString();
  final offset = pending.offset ?? ends[key];
  if (offset == null) {
    throw const AppException('สตรีมนี้ระบุช่วงไบต์ไม่ครบ');
  }
  ends[key] = offset + pending.length;
  return HlsByteRange(offset, pending.length);
}

Uint8List mediaPayload(Uint8List raw) {
  if (raw.isEmpty || raw[0] == 0x47) return raw;
  final jpeg = raw.length >= 2 && raw[0] == 0xFF && raw[1] == 0xD8;
  if (!jpeg) return raw;
  final limit = raw.length - 188;
  for (var index = 0; index < limit; index++) {
    if (raw[index] == 0x47 && raw[index + 188] == 0x47) {
      return Uint8List.sublistView(raw, index);
    }
  }
  return raw;
}

Uri? _resolve(Uri base, String line) {
  try {
    return base.resolve(line);
  } on FormatException {
    return null;
  }
}

String? _attr(String line, String name) {
  final match = RegExp('$name=("([^"]*)"|[^,]*)').firstMatch(line);
  if (match == null) return null;
  final quoted = match.group(2);
  if (quoted != null) return quoted;
  return match.group(1);
}

int? _attrInt(String line, String name) {
  final raw = _attr(line, name);
  if (raw == null) return null;
  return int.tryParse(raw);
}

HlsKey? _key(String line, Uri base) {
  final method = (_attr(line, 'METHOD') ?? '').toUpperCase();
  if (method.isEmpty || method == 'NONE') return null;
  if (method != 'AES-128') {
    throw const AppException('สตรีมนี้ใช้การเข้ารหัสที่แอปยังถอดไม่ได้');
  }
  final uri = _attr(line, 'URI');
  if (uri == null || uri.isEmpty) {
    throw const AppException('สตรีมนี้ไม่มีคีย์ให้ถอดรหัส');
  }
  final iv = _iv(_attr(line, 'IV'));
  return HlsKey(uri: base.resolve(uri), iv: iv);
}

Uint8List? _iv(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final hex = raw.toLowerCase().startsWith('0x') ? raw.substring(2) : raw;
  if (hex.length != 32) {
    throw const AppException('ค่า IV ของสตรีมนี้ใช้ไม่ได้');
  }
  final bytes = Uint8List(16);
  for (var index = 0; index < 16; index++) {
    final value = int.tryParse(
      hex.substring(index * 2, index * 2 + 2),
      radix: 16,
    );
    if (value == null) throw const AppException('ค่า IV ของสตรีมนี้ใช้ไม่ได้');
    bytes[index] = value;
  }
  return bytes;
}
