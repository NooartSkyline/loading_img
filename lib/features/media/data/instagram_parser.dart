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

  static String? shortcodeOf(Uri uri) => _shortcode.firstMatch(uri.toString())?.group(1);

  static Uri embedUri(Uri uri) {
    final code = shortcodeOf(uri);
    if (code == null) {
      throw const AppException('ลิงก์ Instagram ไม่ใช่โพสต์หรือรีล');
    }
    final kind = uri.path.toLowerCase().contains('reel') ? 'reel' : 'p';
    return Uri.https('www.instagram.com', '/$kind/$code/embed/captioned/');
  }

  ResolvedPost parse(String html, Uri pageUrl) {
    final title = metaContent(html, 'og:title');
    final videos = extractUrls(html, r'"video_url"\s*:\s*"([^"]+)"');
    final images = extractUrls(html, r'"display_url"\s*:\s*"([^"]+)"');
    final thumbs = extractUrls(html, r'"thumbnail_src"\s*:\s*"([^"]+)"');
    if (videos.isEmpty && images.isEmpty) {
      throw const AppException(
        'ดึงสื่อจากโพสต์นี้ไม่ได้ โพสต์อาจไม่สาธารณะ หรือ Instagram ไม่ได้ใส่ไฟล์ในหน้านี้',
      );
    }

    final items = <MediaItem>[];
    if (videos.isNotEmpty) {
      for (var i = 0; i < videos.length; i++) {
        items.add(
          MediaItem(
            id: 'ig-video-$i',
            kind: MediaKind.video,
            title: title,
            thumbnailUrl: _thumb(i, thumbs, images),
            variants: [
              MediaVariant(id: 'file', label: 'ต้นฉบับ', url: videos[i]),
            ],
          ),
        );
      }
      for (var i = videos.length; i < images.length; i++) {
        items.add(_image(i, images[i], title));
      }
    } else {
      for (var i = 0; i < images.length; i++) {
        items.add(_image(i, images[i], title));
      }
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
