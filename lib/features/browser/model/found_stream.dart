import 'package:equatable/equatable.dart';
import 'package:loading/core/format_bytes.dart';

class FoundStream extends Equatable {
  const FoundStream({
    required this.url,
    required this.label,
    required this.playlist,
    this.bytes,
    this.audioUrl,
    this.audioOnly = false,
  });

  final String url;
  final String label;
  final bool playlist;
  final int? bytes;
  final String? audioUrl;
  final bool audioOnly;

  String get id => url;

  String get caption {
    final size = bytes;
    if (size == null || size <= 0) return label;
    final text = playlist ? 'ประมาณ ${formatBytes(size)}' : formatBytes(size);
    return '$label · $text';
  }

  FoundStream withBytes(int bytes) {
    return FoundStream(
      url: url,
      label: label,
      playlist: playlist,
      bytes: bytes,
      audioUrl: audioUrl,
      audioOnly: audioOnly,
    );
  }

  FoundStream withAudio(String audioUrl) {
    return FoundStream(
      url: url,
      label: label,
      playlist: playlist,
      bytes: bytes,
      audioUrl: audioUrl,
      audioOnly: audioOnly,
    );
  }

  bool get master => playlist && _isMasterPath(Uri.parse(url));

  String get tree {
    final uri = Uri.parse(url);
    final parts = [...uri.pathSegments];
    if (parts.isNotEmpty) parts.removeLast();
    if (parts.isNotEmpty && _qualities.contains(parts.last)) parts.removeLast();
    return '${uri.host}/${parts.join('/')}';
  }

  String get identity {
    final uri = Uri.tryParse(url);
    final type = uri?.queryParameters['type'];
    final track = uri?.queryParameters['ct'];
    if (type != null && (track == '11' || track == '12')) {
      return '$tree/dash/$type';
    }
    return master
        ? '$tree/master'
        : '$tree/${_qualityOf(label) ?? (playlist ? 'hls' : 'file')}';
  }

  int get rank {
    final size = RegExp(r'(\d+)[x×](\d+)').firstMatch(label);
    final height = size == null ? null : int.tryParse(size.group(2) ?? '');
    if (height != null) return 10000 + height;
    final quality = _qualityOf(label);
    if (quality != null) return 10000 + (int.tryParse(quality) ?? 0);
    if (master) return 50000;
    if (playlist) return 4000;
    return 1;
  }

  @override
  List<Object?> get props => [url, label, playlist, bytes, audioUrl, audioOnly];
}

const _qualities = {'144', '240', '360', '480', '720', '1080', '1440', '2160'};

final _vkVideoId = RegExp(r'(?:video|clip|live)-?\d+_(\d{6,})');

String? dashClipId(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final track = uri.queryParameters['ct'];
  if (track != '11' && track != '12') return null;
  final id = uri.queryParameters['id'];
  if (id == null || id.isEmpty) return null;
  return id;
}

FoundStream? foundStreamFromUrl(String raw) {
  final uri = _withoutByteRange(raw);
  if (uri == null || uri.host.isEmpty) return null;
  if (_dashAudio(uri)) {
    return FoundStream(
      url: uri.toString(),
      label: 'เสียง',
      playlist: false,
      audioOnly: true,
    );
  }
  if (_noise(uri)) return null;
  if (_dashVideo(uri)) {
    return FoundStream(url: uri.toString(), label: 'วิดีโอ', playlist: false);
  }
  final playlist = _playlist(uri);
  final file = _file(uri);
  if (!playlist && !file) return null;
  return FoundStream(
    url: uri.toString(),
    label: _label(uri, playlist),
    playlist: playlist,
  );
}

List<FoundStream> addFoundStream(
  List<FoundStream> current,
  FoundStream next, {
  String? page,
}) {
  final streams = [...current];
  final index = streams.indexWhere((item) => item.identity == next.identity);
  if (index >= 0) {
    final previous = streams[index];
    if (next.rank <= previous.rank) return _present(current, page);
    final kept =
        next.bytes ?? (next.url == previous.url ? previous.bytes : null);
    streams[index] = kept == null ? next : next.withBytes(kept);
  } else {
    streams.add(next);
  }
  return _present(streams, page);
}

List<FoundStream> _present(List<FoundStream> streams, String? page) {
  final visible = _oneClip(_underMaster(_forPage(streams, page)));
  visible.sort((a, b) => b.rank.compareTo(a.rank));
  return visible;
}

List<FoundStream> _oneClip(List<FoundStream> streams) {
  String? clip;
  for (final stream in streams) {
    clip = dashClipId(stream.url);
    if (clip != null) break;
  }
  if (clip == null) return streams;
  return [
    for (final stream in streams)
      if (dashClipId(stream.url) == null || dashClipId(stream.url) == clip)
        stream,
  ];
}

List<FoundStream> _forPage(List<FoundStream> streams, String? page) {
  final id = page == null ? null : _vkVideoId.firstMatch(page)?.group(1);
  if (id == null) return streams;
  final matched = streams.where((stream) => stream.url.contains(id)).toList();
  if (matched.isEmpty) return streams;
  return matched;
}

List<FoundStream> _underMaster(List<FoundStream> streams) {
  final masters = streams
      .where((stream) => stream.master)
      .map((stream) => stream.tree)
      .toSet();
  if (masters.isEmpty) return streams;
  return [
    for (final stream in streams)
      if (stream.master ||
          !masters.any(
            (tree) => stream.tree == tree || stream.tree.startsWith('$tree/'),
          ))
        stream,
  ];
}

bool _noise(Uri uri) {
  final path = uri.path.toLowerCase();
  final name = _name(uri);
  if (path.contains('/ad/') || uri.query.toLowerCase().contains('adserver')) {
    return true;
  }
  if (_preview(uri)) return true;
  if (name.startsWith('init.') ||
      name.startsWith('init-') ||
      name.startsWith('init_')) {
    return true;
  }
  return _segmentName(uri);
}

bool _preview(Uri uri) {
  final name = _name(uri);
  if (name.contains('preview') ||
      name.contains('storyboard') ||
      name.contains('thumbnail')) {
    return true;
  }
  for (final part in uri.pathSegments) {
    final lower = part.toLowerCase();
    if (lower == 'preview' || lower == 'storyboard' || lower == 'thumbnails') {
      return true;
    }
  }
  return uri.queryParameters['preview'] == '1' ||
      uri.queryParameters['thumbnail'] == '1';
}

bool _segmentName(Uri uri) {
  final name = _name(uri);
  if (RegExp(
    r'(?:seg|segment|chunk|frag|fragment|part)[-_]?\d+\.(?:mp4|m4v|m4s|webm|mov|ts)$',
  ).hasMatch(name)) {
    return true;
  }
  final numeric = RegExp(r'^(\d+)\.(?:mp4|m4v|webm|mov)$').firstMatch(name);
  if (numeric == null) return false;
  final value = numeric.group(1);
  if (value == null || _qualities.contains(value)) return false;
  if (value.startsWith('0')) return true;
  return value.length < 6;
}

Uri? _withoutByteRange(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  final query = uri.query
      .split('&')
      .where((part) => part.split('=').first != 'bytes')
      .join('&');
  if (query == uri.query) return uri;
  return uri.replace(query: query);
}

bool _dashVideo(Uri uri) => _dashTrack(uri, '11');

bool _dashAudio(Uri uri) => _dashTrack(uri, '12');

bool _dashTrack(Uri uri, String track) {
  if (!_cdn(uri) || uri.queryParameters['ct'] != track) return false;
  final type = uri.queryParameters['type'];
  if (type == null) return false;
  return RegExp(r'^\d+$').hasMatch(type);
}

bool _playlist(Uri uri) {
  if (_dashVideo(uri) || _dashAudio(uri)) return false;
  final path = uri.path.toLowerCase();
  if (path.endsWith('.m3u8')) return true;
  if (_segmentName(uri) || _fileExtension(path)) return false;
  if (!_cdn(uri)) return false;
  final query = uri.query.toLowerCase();
  if (query.contains('type=2') || query.contains('.m3u8')) return true;
  return RegExp(r'/type/2(?:/|$)').hasMatch(path);
}

bool _file(Uri uri) {
  final path = uri.path.toLowerCase();
  if (_fileExtension(path)) return true;
  if (_segmentName(uri) || !_cdn(uri)) return false;
  final query = uri.query.toLowerCase();
  if (query.contains('type=4')) return true;
  return RegExp(r'/type/4(?:/|$)').hasMatch(path);
}

bool _fileExtension(String path) {
  return path.endsWith('.mp4') ||
      path.endsWith('.m4v') ||
      path.endsWith('.webm') ||
      path.endsWith('.mov');
}

bool _cdn(Uri uri) {
  final host = uri.host.toLowerCase();
  return host.contains('okcdn') ||
      host.contains('mycdn') ||
      host.contains('vkvd') ||
      host.contains('userapi') ||
      host.contains('vkuser') ||
      host.contains('vkuservideo');
}

String _name(Uri uri) {
  if (uri.pathSegments.isEmpty) return '';
  return uri.pathSegments.last.toLowerCase();
}

bool _isMasterPath(Uri uri) {
  final path = uri.path.toLowerCase();
  if (RegExp(r'/(?:144|240|360|480|720|1080|1440|2160)/').hasMatch(path)) {
    return false;
  }
  final name = uri.pathSegments.isEmpty
      ? ''
      : uri.pathSegments.last.toLowerCase();
  return name == 'playlist.m3u8' ||
      name == 'master.m3u8' ||
      name == 'index.m3u8' ||
      name == 'video.m3u8';
}

String? _qualityOf(String label) {
  return RegExp(
    r'(144|240|360|480|720|1080|1440|2160)',
  ).firstMatch(label)?.group(1);
}

String _label(Uri uri, bool playlist) {
  final size = RegExp(r'(\d{3,4})x(\d{3,4})').firstMatch(uri.path);
  if (size != null) return '${size.group(1)}×${size.group(2)}';
  final quality = RegExp(
    r'(?:^|[^\d])(144|240|360|480|720|1080|1440|2160)(?:[^\d]|$)',
  ).firstMatch(uri.path);
  if (quality != null) return '${quality.group(1)}p';
  if (playlist && _isMasterPath(uri)) return 'คุณภาพสูงสุด';
  if (!playlist) return 'วิดีโอ';
  return 'สตรีม';
}
