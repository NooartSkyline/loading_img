import 'package:loading/features/media/data/embedded_text.dart';
import 'package:loading/features/media/model/media_item.dart';
import 'package:loading/features/media/model/media_kind.dart';
import 'package:loading/features/media/model/media_variant.dart';
import 'package:loading/features/media/model/resolved_post.dart';

class VkParser {
  static final _clip = RegExp(r'(?:video|clip|live)(-?\d+)_(\d+)');

  List<Uri> pagesFor(Uri input) {
    final match = _clip.firstMatch('${input.path}${input.query}');
    if (match == null) return [input];
    final oid = match.group(1);
    final id = match.group(2);
    if (oid == null || id == null) return [input];
    final embed = Uri.https('vk.com', '/video_ext.php', {
      'oid': oid,
      'id': id,
      'hd': '2',
    });
    return [embed, input];
  }

  ResolvedPost? parse(String html, Uri source) {
    final title = metaContent(html, 'og:title');
    final videoId = _clip.firstMatch('${source.path}${source.query}')?.group(2);
    final videos = _videoVariants(html, videoId: videoId);
    final images = videoId == null ? _images(html) : const <String>[];
    if (videos.isEmpty && images.isEmpty) return null;

    final items = <MediaItem>[];
    if (videos.isNotEmpty) {
      items.add(
        MediaItem(
          id: 'vk-video-0',
          kind: MediaKind.video,
          title: title,
          thumbnailUrl: images.isEmpty ? null : images.first,
          variants: [
            for (var i = 0; i < videos.length; i++)
              MediaVariant(
                id: 'q$i',
                label: videos[i].label,
                url: videos[i].url,
              ),
          ],
        ),
      );
    } else {
      for (var i = 0; i < images.length; i++) {
        items.add(
          MediaItem(
            id: 'vk-image-$i',
            kind: MediaKind.image,
            title: title,
            thumbnailUrl: images[i],
            variants: [
              MediaVariant(id: 'file', label: 'ต้นฉบับ', url: images[i]),
            ],
          ),
        );
      }
    }

    return ResolvedPost(
      sourceUrl: source.toString(),
      referer: 'https://vk.com/',
      platformLabel: 'VK',
      title: title,
      items: items,
    );
  }

  List<MediaVariant> _videoVariants(String html, {String? videoId}) {
    final expression = RegExp(
      r'"(?:id|video_id)"\s*:\s*"?(\d{2,})"?|"(?:url|mp4_)(144|240|360|480|720|1080|1440|2160)"\s*:\s*"([^"]+)"',
    );
    final buckets = <String, Map<String, String>>{};
    var current = '';
    final loosened = html.replaceAll(r'\"', '"');
    for (final match in expression.allMatches(loosened)) {
      final id = match.group(1);
      if (id != null) {
        current = id;
        continue;
      }
      final quality = match.group(2);
      final raw = match.group(3);
      if (quality == null || raw == null) continue;
      final url = httpUrlOf(raw);
      if (url == null || !_isVkMedia(url)) continue;
      final bucket = buckets.putIfAbsent(current, () => {});
      final existing = bucket[quality];
      if (existing == null ||
          (videoId != null &&
              !existing.contains(videoId) &&
              url.contains(videoId))) {
        bucket[quality] = url;
      }
    }
    final chosen = _chosenVideo(buckets, videoId);
    final found = [
      for (final entry in chosen.entries)
        MediaVariant(id: entry.key, label: '${entry.key}p', url: entry.value),
    ];
    found.sort((a, b) => _pixels(b.label).compareTo(_pixels(a.label)));
    return found;
  }

  Map<String, String> _chosenVideo(
    Map<String, Map<String, String>> buckets,
    String? videoId,
  ) {
    final target = videoId == null ? null : buckets[videoId];
    if (target != null && target.isNotEmpty) return target;
    for (final bucket in buckets.values) {
      if (bucket.isNotEmpty) return bucket;
    }
    return const {};
  }

  List<String> _images(String html) {
    const keys = ['max_src', 'src_xxxbig', 'src_xxbig', 'src_xbig', 'src_big'];
    for (final key in keys) {
      final urls = extractUrls(
        html,
        '"$key"\\s*:\\s*"([^"]+)"',
      ).where(_isVkMedia).toList();
      if (urls.isNotEmpty) return urls;
    }
    return const [];
  }

  bool _isVkMedia(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    final cdn =
        host.contains('userapi') ||
        host.contains('vkuser') ||
        host.contains('vkuservideo') ||
        host.contains('okcdn') ||
        host.contains('vkvideo') ||
        host.contains('mycdn') ||
        host.contains('vk.me');
    final file =
        path.endsWith('.mp4') ||
        path.endsWith('.mov') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.webp');
    return cdn || file;
  }

  int _pixels(String label) {
    final match = RegExp(r'(\d+)').firstMatch(label);
    final raw = match?.group(1);
    if (raw == null) return 0;
    return int.tryParse(raw) ?? 0;
  }
}
