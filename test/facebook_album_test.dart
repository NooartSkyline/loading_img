import 'package:flutter_test/flutter_test.dart';
import 'package:loading/core/app_exception.dart';
import 'package:loading/features/media/data/facebook_parser.dart';
import 'package:loading/features/media/data/facebook_session.dart';
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

  test('facebook share skips the cover page and keeps the album', () async {
    final parser = FacebookParser();
    const share = 'https://www.facebook.com/share/p/1CvKCZPSki/';
    const cover =
        'https://www.facebook.com/share/p/1CvKCZPSki/?hpir=1&http_ref=thin';
    final album = Uri.parse(
      share,
    ).replace(queryParameters: {'hpir': '1'}).toString();
    final pages = _Pages({
      share:
          '<script>window.location.replace("$cover");</script><meta property="og:image" content="https://scontent.xx.fbcdn.net/v/t39.30808-6/1_111111111111_9_n.jpg" />',
      cover:
          '<meta property="og:title" content="ปกอย่างเดียว" /><meta property="og:image" content="https://scontent.xx.fbcdn.net/v/t39.30808-6/1_111111111111_9_n.jpg?stp=cp0_dst-jpg_e15_fr_q65" />',
      album: '''
        <meta property="og:title" content="อัลบั้ม" />
        <img src="https://scontent.xx.fbcdn.net/v/t39.30808-6/1_111111111111_9_n.jpg?stp=dst-webp_p394x394_q70" />
        <img src="https://scontent.xx.fbcdn.net/v/t39.30808-6/2_222222222222_9_n.jpg?stp=dst-webp_p394x394_q70" />
        (dkc "photo_fbid") (dkc "1000")
        (dkc "photo_fbid") (dkc "1006")
        "story_fbid":"5000"
      ''',
      parser.photoPage('1000', expanded: true).toString():
          '''
        ${_photo('111111111111')}
        "story_fbid":"5000"
      ''',
      parser.photoPage('1006', expanded: true).toString():
          '''
        ${_photo('222222222222')}
        "story_fbid":"5000"
      ''',
    });

    final post = await MediaRepository(pages: pages).resolve(share);

    expect(post.items, hasLength(2));
    expect(post.title, 'อัลบั้ม');
    expect(pages.requested, contains(album));
  });

  test(
    'facebook album keeps photos when only some photo pages match',
    () async {
      final parser = FacebookParser();
      const share = 'https://www.facebook.com/share/p/mix/';
      final pages = _Pages({
        share: '''
        <meta property="og:title" content="ผสม" />
        <img src="https://scontent.xx.fbcdn.net/v/t51.82787-15/1_111111111111_9_n.jpg?stp=dst-webp_p394x394_q70" />
        <img src="https://scontent.xx.fbcdn.net/v/t39.30808-6/2_222222222222_9_n.jpg?stp=dst-webp_p394x394_q70" />
        <img src="https://scontent.xx.fbcdn.net/v/t39.30808-6/3_333333333333_9_o.jpg?stp=dst-webp_p394x394_q70" />
        "photo_fbid":"1000"
        "photo_fbid":"1006"
        "photo_fbid":"1007"
        "story_fbid":"5000"
      ''',
        parser.photoPage('1000', expanded: true).toString():
            '''
        ${_photo('111111111111')}
        "story_fbid":"5000"
      ''',
        parser.photoPage('1006', expanded: true).toString():
            '''
        ${_photo('222222222222')}
        "story_fbid":"8888"
      ''',
        parser.photoPage('1007', expanded: true).toString():
            '''
        ${_photo('333333333333')}
        "story_fbid":"8888"
      ''',
      });

      final post = await MediaRepository(pages: pages).resolve(share);

      expect(post.items, hasLength(3));
      expect(post.items.map((item) => item.variants.single.url), [
        contains('111111111111'),
        contains('222222222222'),
        contains('333333333333'),
      ]);
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

  test('a facebook page without files asks for login', () {
    const share = 'https://www.facebook.com/share/p/abc/';
    final pages = _Pages({
      share: '''
        <meta property="og:url" content="https://www.facebook.com/login/" />
        <meta property="og:title" content="Log in to Facebook" />
      ''',
    });

    expect(
      MediaRepository(
        pages: pages,
        facebookSession: _Session(null),
      ).resolve(share),
      throwsA(isA<FacebookLoginRequired>()),
    );
  });

  test('a public facebook photo is used before the saved session', () async {
    const share = 'https://www.facebook.com/share/p/1CQQT6rifZ/';
    final pages = _Pages({
      share: '''
        <meta property="og:title" content="อาภาศ" />
        <meta property="og:image" content="https://scontent.fbkk22-2.fna.fbcdn.net/v/t39.30808-6/894253822_29686377414280557_1318679123233395046_n.jpg?stp=cp0_dst-jpg" />
      ''',
    });

    final post = await MediaRepository(
      pages: pages,
      facebookSession: _Session('c_user=1; xs=token'),
    ).resolve(share);

    expect(post.items.single.kind, MediaKind.image);
    expect(pages.seenCookie, isNull);
  });

  test(
    'a saved facebook session is used when the public page is a login wall',
    () async {
      const share = 'https://www.facebook.com/watch/?v=1';
      final pages = _Pages(
        {
          share: '''
          <meta property="og:url" content="https://www.facebook.com/login/" />
          <meta property="og:title" content="Log in to Facebook" />
        ''',
        },
        signedInHtml: '''
        "browser_native_hd_url":"https://video.xx.fbcdn.net/hd.mp4"
      ''',
      );
      final post = await MediaRepository(
        pages: pages,
        facebookSession: _Session('c_user=1; xs=token'),
      ).resolve(share);

      expect(post.items.single.kind, MediaKind.video);
      expect(pages.seenCookie, 'c_user=1; xs=token');
    },
  );

  test('a rejected facebook session is forgotten and asks to log in', () async {
    const share = 'https://www.facebook.com/share/p/private/';
    const wall = '''
      <meta property="og:url" content="https://www.facebook.com/login/" />
      <meta property="og:title" content="Log in to Facebook" />
    ''';
    final session = _Session('c_user=1; xs=token');
    final pages = _Pages({share: wall}, signedInHtml: wall);

    await expectLater(
      MediaRepository(pages: pages, facebookSession: session).resolve(share),
      throwsA(isA<FacebookLoginRequired>()),
    );
    expect(session.forgotten, isTrue);
  });

  test('facebook session needs both the user and the token', () {
    expect(facebookSignedIn('c_user=1; xs=token'), isTrue);
    expect(facebookSignedIn('c_user=1'), isFalse);
    expect(facebookSignedIn('xs=token'), isFalse);
  });
}

String _photo(String fileId) {
  return '''
    <meta property="og:image" content="https://scontent.xx.fbcdn.net/v/t39.30808-6/1_${fileId}_9_n.jpg?stp=cp0_dst-jpg_e15_fr_q65" />
  ''';
}

class _Pages extends PageClient {
  _Pages(this.htmlByUrl, {this.signedInHtml});

  final Map<String, String> htmlByUrl;
  final String? signedInHtml;
  final requested = <String>[];
  String? seenCookie;

  @override
  Future<String> getHtml(Uri uri, {String? cookie}) async {
    seenCookie = cookie;
    requested.add(uri.toString());
    if (cookie != null && signedInHtml != null) return signedInHtml!;
    final html = htmlByUrl[uri.toString()];
    if (html == null) throw AppException('ไม่มีหน้า $uri');
    return html;
  }
}

class _Session implements FacebookSession {
  _Session(this.cookie);

  final String? cookie;
  var forgotten = false;

  @override
  Future<String?> cookieHeader() async => cookie;

  @override
  Future<void> forget() async {
    forgotten = true;
  }
}
