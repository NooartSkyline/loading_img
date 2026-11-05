import 'package:loading/core/app_exception.dart';

String decodeEmbedded(String raw) {
  var text = raw.trim();
  var previous = '';
  while (text != previous) {
    previous = text;
    text = text.replaceAll(r'\"', '"');
    text = text.replaceAll(r'\/', '/');
    text = text.replaceAll(r'\%', '%');
    text = text.replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})'), (match) {
      final hex = match.group(1);
      if (hex == null) return match.group(0) ?? '';
      return String.fromCharCode(int.parse(hex, radix: 16));
    });
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }
  return text.replaceAll('\\', '');
}

String? httpUrlOf(String raw) {
  var decoded = decodeEmbedded(raw).trim();
  if (decoded.isEmpty) return null;
  if (!decoded.startsWith('http') && decoded.contains('%')) {
    try {
      decoded = Uri.decodeFull(decoded);
    } on FormatException {
      return null;
    }
  }
  final uri = Uri.tryParse(decoded);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  return uri.toString();
}

bool sameResource(String left, String right) {
  final a = Uri.tryParse(left);
  final b = Uri.tryParse(right);
  if (a == null || b == null) return left == right;
  return a.host == b.host && a.path == b.path;
}

List<String> uniqueUrls(Iterable<String> urls) {
  final seen = <String>{};
  final result = <String>[];
  for (final url in urls) {
    final uri = Uri.tryParse(url);
    final key = uri == null ? url : '${uri.host}${uri.path}';
    if (seen.add(key)) result.add(url);
  }
  return result;
}

List<String> extractUrls(String html, String pattern) {
  final expression = RegExp(pattern, caseSensitive: false);
  final urls = <String>[];
  final loosened = html.replaceAll(r'\"', '"');
  for (final source in loosened == html ? [html] : [html, loosened]) {
    for (final match in expression.allMatches(source)) {
      final raw = match.group(1);
      if (raw == null || raw.isEmpty) continue;
      final url = httpUrlOf(raw);
      if (url != null) urls.add(url);
    }
  }
  return uniqueUrls(urls);
}

String? metaContent(String html, String property) {
  final escaped = RegExp.escape(property);
  final propertyFirst = RegExp(
    '<meta[^>]+(?:property|name)=["\']$escaped["\'][^>]+content=["\']([^"\']+)["\']',
    caseSensitive: false,
  );
  final contentFirst = RegExp(
    '<meta[^>]+content=["\']([^"\']+)["\'][^>]+(?:property|name)=["\']$escaped["\']',
    caseSensitive: false,
  );
  final raw = propertyFirst.firstMatch(html)?.group(1) ??
      contentFirst.firstMatch(html)?.group(1);
  if (raw == null || raw.trim().isEmpty) return null;
  return decodeEmbedded(raw);
}

String safeFileName(String name) {
  final cleaned = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  if (cleaned.isEmpty) return 'media';
  if (cleaned.length <= 80) return cleaned;
  return cleaned.substring(0, 80);
}

Uri parseUserUrl(String raw) {
  var text = raw.trim();
  if (text.isEmpty) throw const AppException('ใส่ลิงก์ก่อน');
  text = text.replaceFirst(
    RegExp(r'^(?:ttps|htps)://', caseSensitive: false),
    'https://',
  );
  text = text.replaceFirst(
    RegExp(r'^(?:ttp|htp)://', caseSensitive: false),
    'http://',
  );
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    throw const AppException('ลิงก์ต้องขึ้นต้นด้วย http หรือ https');
  }
  return uri;
}
