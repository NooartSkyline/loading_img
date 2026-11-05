enum MediaPlatform { instagram, facebook, vk, direct, unknown }

MediaPlatform detectPlatform(Uri uri) {
  final host = uri.host.toLowerCase();
  if (host == 'instagram.com' ||
      host.endsWith('.instagram.com') ||
      host == 'instagr.am') {
    return MediaPlatform.instagram;
  }
  if (host == 'facebook.com' ||
      host.endsWith('.facebook.com') ||
      host == 'fb.com' ||
      host.endsWith('.fb.com') ||
      host == 'fb.watch' ||
      host.endsWith('.fb.watch')) {
    return MediaPlatform.facebook;
  }
  if (host == 'vk.com' ||
      host.endsWith('.vk.com') ||
      host == 'vk.ru' ||
      host.endsWith('.vk.ru') ||
      host == 'vkvideo.ru' ||
      host.endsWith('.vkvideo.ru')) {
    return MediaPlatform.vk;
  }
  if (kindFromPath(uri.path) != null) return MediaPlatform.direct;
  return MediaPlatform.unknown;
}

enum FileKindHint { image, video }

FileKindHint? kindFromPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.mp4') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.m4v')) {
    return FileKindHint.video;
  }
  if (lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.gif')) {
    return FileKindHint.image;
  }
  return null;
}

FileKindHint? kindFromType(String? contentType, Uri uri) {
  final type = contentType?.toLowerCase() ?? '';
  if (type.startsWith('video/')) return FileKindHint.video;
  if (type.startsWith('image/')) return FileKindHint.image;
  return kindFromPath(uri.path);
}

String fileExtension({
  required String url,
  required String? contentType,
  required bool video,
}) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  const known = [
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.mp4',
    '.mov',
    '.webm',
    '.m4v',
  ];
  for (final ext in known) {
    if (path.endsWith(ext)) {
      return ext == '.jpeg' ? 'jpg' : ext.substring(1);
    }
  }
  final type = contentType?.toLowerCase() ?? '';
  if (type.contains('png')) return 'png';
  if (type.contains('webp')) return 'webp';
  if (type.contains('gif')) return 'gif';
  if (type.contains('jpeg') || type.contains('jpg')) return 'jpg';
  if (type.contains('webm')) return 'webm';
  if (type.contains('quicktime')) return 'mov';
  if (type.contains('mp4')) return 'mp4';
  return video ? 'mp4' : 'jpg';
}
