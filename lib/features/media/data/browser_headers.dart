const String kBrowserUserAgent =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';

Map<String, String> browserHeaders({
  required String referer,
  String? range,
  String? userAgent,
}) {
  final agent = userAgent?.trim();
  final headers = <String, String>{
    'User-Agent': (agent != null && agent.isNotEmpty)
        ? agent
        : kBrowserUserAgent,
    'Accept': '*/*',
    'Accept-Language': 'th,en;q=0.8',
    'Accept-Encoding': 'identity',
    'Referer': referer,
  };
  final byteRange = range;
  if (byteRange != null) headers['Range'] = byteRange;
  return headers;
}
