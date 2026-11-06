import 'package:loading/core/app_exception.dart';
import 'package:loading/features/media/data/embedded_text.dart';
import 'package:loading/features/media/model/media_item.dart';
import 'package:loading/features/media/model/media_kind.dart';
import 'package:loading/features/media/model/media_variant.dart';
import 'package:loading/features/media/model/resolved_post.dart';

class InstagramParser {
  static final _shortcode = RegExp(
    r'instagram\.com/(?:share/)?(?:p|reel|reels|tv)/([A-Za-z0-9_-]+)',
    caseSensitive: false,
  );

  static String? shortcodeOf(Uri uri) =>
      _shortcode.firstMatch(uri.toString())?.group(1);

  static String mediaIdOf(String shortcode) {
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    final base = BigInt.from(64);
    var value = BigInt.zero;
    for (final unit in shortcode.codeUnits) {
      final index = alphabet.indexOf(String.fromCharCode(unit));
      if (index < 0) {
        throw const AppException('ลิงก์ Instagram ไม่ใช่โพสต์หรือรีล');
      }
      value = value * base + BigInt.from(index);
    }
    return value.toString();
  }

  static List<Uri> pagesFor(Uri uri) {
    final embed = embedUri(uri);
    final code = shortcodeOf(uri);
    if (code == null) return [embed];
    final reel = uri.path.toLowerCase().contains('reel');
    return [
      embed,
      if (reel) Uri.https('www.instagram.com', '/p/$code/embed/captioned/'),
      Uri.https('www.instagram.com', '/${reel ? 'reel' : 'p'}/$code/'),
    ];
  }

  static Uri embedUri(Uri uri) {
    final code = shortcodeOf(uri);
    if (code == null) {
      throw const AppException('ลิงก์ Instagram ไม่ใช่โพสต์หรือรีล');
    }
    final kind = uri.path.toLowerCase().contains('reel') ? 'reel' : 'p';
    return Uri.https('www.instagram.com', '/$kind/$code/embed/captioned/');
  }

  ResolvedPost parse(String html, Uri pageUrl) => read(html, pageUrl).post;

  InstagramRead read(String html, Uri pageUrl) {
    final title = metaContent(html, 'og:title');
    final videos = extractUrls(html, r'"video_url"\s*:\s*"([^"]+)"');
    final images = extractUrls(html, r'"display_url"\s*:\s*"([^"]+)"');
    final thumbs = extractUrls(html, r'"thumbnail_src"\s*:\s*"([^"]+)"');
    final pageVideo = videos.isEmpty ? _pageFile(html, 'og:video') : null;
    final pageImage = images.isEmpty ? _pageFile(html, 'og:image') : null;
    final foundVideos = [...videos, ?pageVideo];
    final foundImages = [
      ...images,
      if (images.isEmpty && pageImage != null) pageImage,
    ];
    if (foundVideos.isEmpty && foundImages.isEmpty) {
      throw const AppException(
        'ดึงสื่อจากโพสต์นี้ไม่ได้ โพสต์อาจไม่สาธารณะ หรือ Instagram ไม่ได้ใส่ไฟล์ในหน้านี้',
      );
    }

    final items = <MediaItem>[];
    if (foundVideos.isNotEmpty) {
      for (var i = 0; i < foundVideos.length; i++) {
        items.add(
          MediaItem(
            id: 'ig-video-$i',
            kind: MediaKind.video,
            title: title,
            thumbnailUrl: _thumb(i, thumbs, foundImages),
            variants: [
              MediaVariant(id: 'file', label: 'ต้นฉบับ', url: foundVideos[i]),
            ],
          ),
        );
      }
      for (var i = foundVideos.length; i < foundImages.length; i++) {
        items.add(_image(i, foundImages[i], title));
      }
    } else {
      for (var i = 0; i < foundImages.length; i++) {
        items.add(_image(i, foundImages[i], title));
      }
    }

    final coverOnly = videos.isEmpty && images.isEmpty && foundVideos.isEmpty;
    return InstagramRead(
      ResolvedPost(
        sourceUrl: pageUrl.toString(),
        referer: 'https://www.instagram.com/',
        platformLabel: 'Instagram',
        title: title,
        items: items,
        initialSelectedIds: _selectedFromIndex(pageUrl, items),
      ),
      coverOnly: coverOnly,
    );
  }

  ResolvedPost postFromMediaInfo(Map<String, dynamic> json, Uri pageUrl) {
    final rawItems = json['items'];
    if (rawItems is! List || rawItems.isEmpty || rawItems.first is! Map) {
      throw const AppException('โพสต์นี้ไม่มีไฟล์ให้โหลด');
    }
    final media = Map<String, dynamic>.from(rawItems.first as Map);
    final slides = media['carousel_media'];
    final nodes = slides is List && slides.isNotEmpty ? slides : [media];
    final title = _caption(media);
    final items = <MediaItem>[];
    for (final node in nodes) {
      if (node is! Map) continue;
      final entry = Map<String, dynamic>.from(node);
      final id = '${entry['pk'] ?? items.length}';
      final video = _widestUrl(entry['video_versions']);
      final image = _widestUrl(entry['image_versions2']);
      if (video != null) {
        items.add(
          MediaItem(
            id: 'ig-video-$id',
            kind: MediaKind.video,
            title: title,
            thumbnailUrl: image ?? video,
            variants: [MediaVariant(id: 'file', label: 'ต้นฉบับ', url: video)],
          ),
        );
      } else if (image != null) {
        items.add(
          MediaItem(
            id: 'ig-image-$id',
            kind: MediaKind.image,
            title: title,
            thumbnailUrl: image,
            variants: [MediaVariant(id: 'file', label: 'ต้นฉบับ', url: image)],
          ),
        );
      }
    }
    if (items.isEmpty) {
      throw const AppException('โพสต์นี้ไม่มีไฟล์ให้โหลด');
    }
    return ResolvedPost(
      sourceUrl: pageUrl.toString(),
      referer: 'https://www.instagram.com/',
      platformLabel: 'Instagram',
      title: title,
      items: items,
      initialSelectedIds: _selectedFromIndex(pageUrl, items),
    );
  }

  String? _caption(Map<String, dynamic> media) {
    final caption = media['caption'];
    if (caption is Map && caption['text'] is String) {
      final text = (caption['text'] as String).trim();
      if (text.isNotEmpty) return text;
    }
    final user = media['user'];
    if (user is Map && user['username'] is String) {
      final name = (user['username'] as String).trim();
      if (name.isNotEmpty) return name;
    }
    return null;
  }

  String? _widestUrl(Object? source) {
    final candidates = source is Map
        ? source['candidates']
        : source is List
        ? source
        : null;
    if (candidates is! List) return null;
    String? best;
    var width = -1;
    for (final candidate in candidates) {
      if (candidate is! Map) continue;
      final url = candidate['url'];
      if (url is! String || !url.startsWith('http')) continue;
      final rawWidth = candidate['width'];
      final pixels = rawWidth is int
          ? rawWidth
          : int.tryParse('$rawWidth') ?? 0;
      if (pixels >= width) {
        width = pixels;
        best = url;
      }
    }
    return best;
  }

  String? _pageFile(String html, String property) {
    final raw = metaContent(html, property);
    if (raw == null) return null;
    final url = httpUrlOf(raw);
    if (url == null) return null;
    final host = Uri.parse(url).host.toLowerCase();
    if (host.contains('static.cdninstagram.com')) return null;
    if (host.contains('cdninstagram') || host.contains('fbcdn')) return url;
    return null;
  }

  List<String> _selectedFromIndex(Uri pageUrl, List<MediaItem> items) {
    final raw = pageUrl.queryParameters['img_index'];
    final index = raw == null ? null : int.tryParse(raw);
    if (index == null || index < 1 || index > items.length) return const [];
    return [items[index - 1].id];
  }

  String? _thumb(int index, List<String> thumbs, List<String> images) {
    if (index < thumbs.length) return thumbs[index];
    if (index < images.length) return images[index];
    if (thumbs.isNotEmpty) return thumbs.first;
    if (images.isNotEmpty) return images.first;
    return null;
  }

  MediaItem _image(int index, String url, String? title) {
    return MediaItem(
      id: 'ig-image-$index',
      kind: MediaKind.image,
      title: title,
      thumbnailUrl: url,
      variants: [MediaVariant(id: 'file', label: 'ต้นฉบับ', url: url)],
    );
  }
}

class InstagramRead {
  const InstagramRead(this.post, {required this.coverOnly});

  final ResolvedPost post;
  final bool coverOnly;
}
