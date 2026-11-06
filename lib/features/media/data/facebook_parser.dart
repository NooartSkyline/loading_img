import 'package:loading/features/media/data/embedded_text.dart';
import 'package:loading/features/media/model/media_item.dart';
import 'package:loading/features/media/model/media_kind.dart';
import 'package:loading/features/media/model/media_variant.dart';
import 'package:loading/features/media/model/resolved_post.dart';

class FacebookParser {
  List<Uri> pagesFor(Uri input) {
    final pages = <Uri>[input];
    final host = input.host.toLowerCase();
    final onFacebook = host.contains('facebook.com') || host.endsWith('fb.com');
    if (onFacebook && !host.startsWith('m.')) {
      pages.add(input.replace(host: 'm.facebook.com'));
    }
    if (input.path.toLowerCase().contains('/stories/')) return pages;
    if (input.queryParameters['hpir'] != '1') {
      pages.add(
        input.replace(queryParameters: {...input.queryParameters, 'hpir': '1'}),
      );
    }
    pages.add(
      Uri.https('www.facebook.com', '/plugins/video.php', {
        'href': input.toString(),
        'show_text': 'false',
      }),
    );
    if (onFacebook) pages.add(input.replace(host: 'mbasic.facebook.com'));
    return pages;
  }

  ResolvedPost? parse(String html, Uri source) {
    final videos = <MediaVariant>[];
    void addVideos(String label, String pattern) {
      for (final url in extractUrls(html, pattern)) {
        final duplicated = videos.any(
          (variant) => sameResource(variant.url, url),
        );
        if (duplicated) continue;
        videos.add(
          MediaVariant(id: 'q${videos.length}', label: label, url: url),
        );
      }
    }

    addVideos('คุณภาพสูง', r'"browser_native_hd_url"\s*:\s*"([^"]+)"');
    addVideos('คุณภาพสูง', r'hd_src(?:"\s*:\s*"|=)([^"&]+)');
    addVideos('คุณภาพมาตรฐาน', r'"playable_url_quality_hd"\s*:\s*"([^"]+)"');
    addVideos('คุณภาพมาตรฐาน', r'"browser_native_sd_url"\s*:\s*"([^"]+)"');
    addVideos('คุณภาพมาตรฐาน', r'"playable_url"\s*:\s*"([^"]+)"');
    addVideos('คุณภาพต่ำ', r'sd_src(?:"\s*:\s*"|=)([^"&]+)');
    final width = metaContent(html, 'og:video:width');
    final height = metaContent(html, 'og:video:height');
    final openGraphLabel = (width != null && height != null)
        ? '$width×$height'
        : 'วิดีโอ';
    addVideos(
      openGraphLabel,
      r'<meta[^>]+property="og:video"[^>]+content="([^"]+)"',
    );
    addVideos(
      openGraphLabel,
      r'<meta[^>]+property="og:video:secure_url"[^>]+content="([^"]+)"',
    );
    if (videos.isEmpty && _isBlockedPage(html)) return null;

    final title = metaContent(html, 'og:title');
    final ogImage = metaContent(html, 'og:image');
    final og = ogImage == null ? null : httpUrlOf(ogImage);
    final images = _stills(html);
    if (images.isEmpty && og != null && _isCdn(og)) images.add(og);
    if (videos.isEmpty && images.isEmpty) return null;

    final items = <MediaItem>[];
    if (videos.isNotEmpty) {
      items.add(
        MediaItem(
          id: 'fb-video-0',
          kind: MediaKind.video,
          title: title,
          thumbnailUrl: og,
          variants: videos,
        ),
      );
    } else {
      final stills = <String>[...images];
      final previewId = og == null ? null : _fileId(og);
      final alreadyListed = previewId != null
          ? stills.any((url) => _fileId(url) == previewId)
          : og != null && stills.any((url) => sameResource(url, og));
      if (og != null && _isCdn(og) && !alreadyListed) stills.insert(0, og);
      for (var i = 0; i < stills.length; i++) {
        items.add(
          MediaItem(
            id: 'fb-image-$i',
            kind: MediaKind.image,
            title: title,
            thumbnailUrl: stills[i],
            variants: [
              MediaVariant(id: 'file', label: 'ต้นฉบับ', url: stills[i]),
            ],
          ),
        );
      }
    }
    if (items.isEmpty) return null;

    return ResolvedPost(
      sourceUrl: source.toString(),
      referer: 'https://www.facebook.com/',
      platformLabel: 'Facebook',
      title: title,
      items: items,
    );
  }

  Uri? redirectTarget(String html) {
    final match = RegExp(
      r'''location\.replace\((?:"([^"]+)"|'([^']+)')\)''',
    ).firstMatch(html);
    final raw = match?.group(1) ?? match?.group(2);
    if (raw == null || raw.isEmpty) return null;
    final uri = Uri.tryParse(decodeEmbedded(raw));
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    final host = uri.host.toLowerCase();
    final onFacebook = host.contains('facebook.com') || host.endsWith('fb.com');
    if (!onFacebook) return null;
    return uri;
  }

  List<String> photoIds(String html) {
    final loose = _loose(html);
    final expressions = [
      RegExp(r'\(dkc "photo_fbid"\) \(dkc "(\d+)"\)'),
      RegExp(r'(?<!target_)photo_fbid\s*:\s*"(\d+)"'),
    ];
    final ids = <String>[];
    final seen = <String>{};
    for (final expression in expressions) {
      for (final match in expression.allMatches(loose)) {
        final id = match.group(1);
        if (id == null || !seen.add(id)) continue;
        ids.add(id);
      }
    }
    return ids;
  }

  String? postId(String html) {
    final counts = <String, int>{};
    for (final match in RegExp(
      r'"story_fbid":"(\d+)"',
    ).allMatches(_loose(html))) {
      final id = match.group(1);
      if (id == null) continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    var best = counts.keys.first;
    var highest = counts[best] ?? 0;
    for (final entry in counts.entries) {
      if (entry.value <= highest) continue;
      best = entry.key;
      highest = entry.value;
    }
    return best;
  }

  bool belongsToStory(String html, String storyId) {
    return RegExp(
      r'"story_fbid":"(\d+)"',
    ).allMatches(_loose(html)).any((match) => match.group(1) == storyId);
  }

  Uri photoPage(String photoId, {bool expanded = false}) {
    return Uri.https('m.facebook.com', '/photo.php', {
      'fbid': photoId,
      if (expanded) 'hpir': '1',
    });
  }

  List<String> linkedPhotoIds(String html) {
    final expression = RegExp(r'target_photo_(?:id|fbid)":"(\d+)"');
    final ids = <String>[];
    final seen = <String>{};
    for (final match in expression.allMatches(_loose(html))) {
      final id = match.group(1);
      if (id == null || !seen.add(id)) continue;
      ids.add(id);
    }
    return ids;
  }

  String? photoFile(String html) {
    if (_isBlockedPage(html)) return null;
    final stills = _stills(html);
    if (stills.isEmpty) return null;
    var best = stills.first;
    var rank = _rank(best);
    for (final url in stills.skip(1)) {
      final next = _rank(url);
      if (next <= rank) continue;
      best = url;
      rank = next;
    }
    return best;
  }

  static final _attachment = RegExp(
    r'https://[^"\s<>),\\]+?/t\d+\.\d+-(?!1/)\d+/\d+_(\d{10,})_\d+_[a-z]\.(?:jpe?g|webp|png)(?:\?[^"\s<>),\\]*)?',
    caseSensitive: false,
  );

  String? fileId(String url) => _fileId(url);

  int fileRank(String url) => _rank(url);

  List<String> _stills(String html) {
    final found = <String, String>{};
    final order = <String>[];
    for (final match in _attachment.allMatches(_loose(html))) {
      final raw = match.group(0);
      final id = match.group(1);
      if (raw == null || id == null) continue;
      final url = httpUrlOf(raw);
      if (url == null || !_isCdn(url)) continue;
      final current = found[id];
      if (current == null) {
        found[id] = url;
        order.add(id);
        continue;
      }
      if (_rank(url) > _rank(current)) found[id] = url;
    }
    final urls = <String>[];
    for (final id in order) {
      final url = found[id];
      if (url != null) urls.add(url);
    }
    return urls;
  }

  String? _fileId(String url) => _attachment.firstMatch(url)?.group(1);

  bool _isCdn(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return host.contains('fbcdn') || host.contains('facebook');
  }

  int _rank(String url) {
    final stp = Uri.tryParse(url)?.queryParameters['stp'] ?? '';
    final size = RegExp(r'(?:^|_)[sp](\d+)x(\d+)').firstMatch(stp);
    if (size != null) {
      final width = int.tryParse(size.group(1) ?? '') ?? 0;
      final height = int.tryParse(size.group(2) ?? '') ?? 0;
      return width * height;
    }
    if (stp.contains('e15') || stp.contains('_fr')) return 100000000;
    if (stp.isEmpty) return 80000000;
    return 50000000;
  }

  String _loose(String html) {
    return html
        .replaceAll(r'\"', '"')
        .replaceAll(r'\/', '/')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll(r'\u0026', '&');
  }

  bool isLoginWall(String html) => _isBlockedPage(html);

  bool _isBlockedPage(String html) {
    final url = (metaContent(html, 'og:url') ?? '').toLowerCase();
    if (url.contains('/login')) return true;
    final title = (metaContent(html, 'og:title') ?? '').toLowerCase();
    if (title.contains('log in') || title.contains('เข้าสู่ระบบ')) return true;
    final lower = html.toLowerCase();
    return lower.contains("browser isn't supported") ||
        lower.contains('browser isn&#039;t supported') ||
        lower.contains('browser isn&#39;t supported');
  }
}
