import 'package:flutter_test/flutter_test.dart';
import 'package:loading/core/app_exception.dart';
import 'package:loading/features/media/data/facebook_parser.dart';
import 'package:loading/features/media/data/media_repository.dart';
import 'package:loading/features/media/data/page_client.dart';
import 'package:loading/features/media/model/media_kind.dart';

void main() {
  test(
    'facebook share link follows the album past the folded photos',
    () async {
      final parser = FacebookParser();
      const share = 'https://www.facebook.com/share/abc/';
      const full = 'https://www.facebook.com/share/abc/?hpir=1';
      final pages = _Pages({
        share:
            '''
        <meta property="og:image" content="https://scontent.xx.fbcdn.net/v/t39.30808-6/1_111111111111_9_n.jpg?stp=dst-webp_q70_s100x100" />
        <script>window.location.replace("$full");</script>
      ''',
        full: '''
        <meta property="og:title" content="Pinxpwd.x" />
        <meta property="og:url" content="https://www.facebook.com/99/posts/1/" />
        <img src="https://scontent.xx.fbcdn.net/v/t39.30808-6/1_111111111111_9_n.jpg?stp=dst-webp_q70_s173x172" />
        <img src="https://scontent.xx.fbcdn.net/v/t39.30808-6/2_222222222222_9_n.jpg?stp=dst-webp_q70_s173x172" />
        (dkc "photo_fbid") (dkc "1000")
        (dkc "photo_fbid") (dkc "1006")
        "story_fbid":"5000"
      ''',
        parser.photoPage('1000', expanded: true).toString():
            '''
        ${_photo('111111111111')}
        "story_fbid":"5000"
        target_photo_id":"1003"
      ''',
        parser.photoPage('1006', expanded: true).toString():
            '''
        ${_photo('222222222222')}
        "story_fbid":"5000"
      ''',
        parser.photoPage('1003', expanded: true).toString():
            '''
        ${_photo('333333333333')}
        "story_fbid":"5000"
        target_photo_id":"9999"
      ''',
        parser.photoPage('9999', expanded: true).toString():
            '''
        ${_photo('999999999999')}
        "story_fbid":"8888"
      ''',
      });
      final post = await MediaRepository(pages: pages).resolve(share);

      expect(post.items, hasLength(3));
      expect(post.items.every((item) => item.kind == MediaKind.image), isTrue);
      expect(post.items.map((item) => item.variants.single.url), [
        contains('111111111111'),
        contains('222222222222'),
        contains('333333333333'),
      ]);
      expect(
        post.items.any(
          (item) => item.variants.single.url.contains('999999999999'),
        ),
        isFalse,
      );
      expect(post.title, 'Pinxpwd.x');
    },
  );

  test('facebook video is not replaced by album photos', () async {
    const share = 'https://www.facebook.com/watch/?v=1';
    final pages = _Pages({
      share: '''
        <meta property="og:image" content="https://scontent.xx.fbcdn.net/cover.jpg" />
        "browser_native_hd_url":"https://video.xx.fbcdn.net/hd.mp4"
        (dkc "photo_fbid") (dkc "1000")
        "story_fbid":"5000"
      ''',
    });
    final post = await MediaRepository(pages: pages).resolve(share);

    expect(post.items, hasLength(1));
    expect(post.items.single.kind, MediaKind.video);
    expect(pages.requested, [share]);
  });
}

String _photo(String fileId) {
  return '''
    <meta property="og:image" content="https://scontent.xx.fbcdn.net/v/t39.30808-6/1_${fileId}_9_n.jpg?stp=cp0_dst-jpg_e15_fr_q65" />
  ''';
}

class _Pages extends PageClient {
  _Pages(this.htmlByUrl);

  final Map<String, String> htmlByUrl;
  final requested = <String>[];

  @override
  Future<String> getHtml(Uri uri) async {
    requested.add(uri.toString());
    final html = htmlByUrl[uri.toString()];
    if (html == null) throw AppException('ไม่มีหน้า $uri');
    return html;
  }
}
