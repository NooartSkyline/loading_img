import 'package:flutter_test/flutter_test.dart';
import 'package:loading/features/media/data/embedded_text.dart';
import 'package:loading/features/media/data/facebook_parser.dart';
import 'package:loading/features/media/data/instagram_parser.dart';
import 'package:loading/features/media/data/platform_detector.dart';
import 'package:loading/features/media/data/vk_parser.dart';
import 'package:loading/features/media/model/media_kind.dart';

void main() {
  test('decodes escaped media urls', () {
    expect(
      httpUrlOf(r'https:\/\/cdn.example\/a.mp4?x=1\u0026y=2'),
      'https://cdn.example/a.mp4?x=1&y=2',
    );
  });

  test('detects the three platforms', () {
    expect(
      detectPlatform(Uri.parse('https://www.instagram.com/reel/abc/')),
      MediaPlatform.instagram,
    );
    expect(
      detectPlatform(Uri.parse('https://fb.watch/abcd/')),
      MediaPlatform.facebook,
    );
    expect(
      detectPlatform(Uri.parse('https://vk.com/video-1_2')),
      MediaPlatform.vk,
    );
    expect(
      detectPlatform(Uri.parse('https://cdn.example/clip.mp4')),
      MediaPlatform.direct,
    );
  });

  test('fixes a missing h in https and keeps the instagram slide', () {
    final uri = parseUserUrl(
      'ttps://www.instagram.com/p/DfUk_-iElt7/?img_index=4&vrfl=abc',
    );
    expect(uri.scheme, 'https');
    expect(uri.path, '/p/DfUk_-iElt7/');
    expect(uri.queryParameters['img_index'], '4');
  });

  test('instagram carousel link selects the requested slide', () {
    final html = [
      r'\"display_url\":\"https:\\\/\\\/instagram.example\/111_n.jpg?k=Mg\\u00253D\"',
      r'\"display_url\":\"https:\\\/\\\/instagram.example\/111_n.jpg?k=dup\"',
      r'\"display_url\":\"https:\\\/\\\/instagram.example\/222_n.jpg\"',
      r'\"display_url\":\"https:\\\/\\\/instagram.example\/333_n.jpg\"',
      r'\"display_url\":\"https:\\\/\\\/instagram.example\/444_n.jpg\"',
    ].join('\n');
    final post = InstagramParser().parse(
      html,
      Uri.parse('https://www.instagram.com/p/DfUJ3lZExVL/?img_index=4'),
    );
    expect(post.items, hasLength(4));
    expect(post.items.first.variants.single.url, contains('111_n.jpg'));
    expect(post.items.first.variants.single.url, contains('k=Mg%3D'));
    expect(post.items[3].variants.single.url, contains('444_n.jpg'));
    expect(post.initialSelectedIds, [post.items[3].id]);
  });

  test('instagram carousel keeps the video and extra stills', () {
    const html = '''
      <meta property="og:title" content="โพสต์ทดสอบ" />
      {"video_url":"https:\\/\\/cdninstagram.com\\/v\\/a.mp4","display_url":"https:\\/\\/cdninstagram.com\\/v\\/a.jpg","thumbnail_src":"https:\\/\\/cdninstagram.com\\/v\\/a.jpg"}
      {"display_url":"https:\\/\\/cdninstagram.com\\/v\\/b.jpg"}
    ''';
    final post = InstagramParser().parse(
      html,
      Uri.parse('https://www.instagram.com/reel/abc/'),
    );
    expect(post.platformLabel, 'Instagram');
    expect(post.items, hasLength(2));
    expect(post.items.first.kind, MediaKind.video);
    expect(
      post.items.first.variants.single.url,
      'https://cdninstagram.com/v/a.mp4',
    );
    expect(post.items.last.kind, MediaKind.image);
    expect(
      post.items.last.variants.single.url,
      'https://cdninstagram.com/v/b.jpg',
    );
  });

  test('facebook groups qualities of one video', () {
    const html = '''
      <meta property="og:image" content="https://scontent.xx.fbcdn.net/cover.jpg" />
      "browser_native_hd_url":"https:\\u002F\\u002Fvideo.xx.fbcdn.net\\u002Fhd.mp4"
      "browser_native_sd_url":"https:\\u002F\\u002Fvideo.xx.fbcdn.net\\u002Fsd.mp4"
    ''';
    final post = FacebookParser().parse(
      html,
      Uri.parse('https://www.facebook.com/watch/?v=1'),
    );
    expect(post, isNotNull);
    expect(post!.items, hasLength(1));
    expect(post.items.single.kind, MediaKind.video);
    expect(post.items.single.variants.map((variant) => variant.label), [
      'คุณภาพสูง',
      'คุณภาพมาตรฐาน',
    ]);
    expect(
      post.items.single.thumbnailUrl,
      'https://scontent.xx.fbcdn.net/cover.jpg',
    );
  });

  test('facebook share page uses the open graph video', () {
    const html = '''
      <meta property="og:url" content="https://www.facebook.com/reel/2320585098738346/" />
      <meta property="og:image" content="https://scontent.fbkk22-1.fna.fbcdn.net/cover.jpg?x=1&amp;y=2" />
      <meta property="og:video" content="https://video.fbkk2-8.fna.fbcdn.net/reel.mp4?x=1&amp;y=2" />
      <meta property="og:video:width" content="1080" />
      <meta property="og:video:height" content="1920" />
    ''';
    final post = FacebookParser().parse(
      html,
      Uri.parse('https://www.facebook.com/share/r/1AK8BH6jxE/'),
    );
    expect(post, isNotNull);
    expect(post!.items.single.kind, MediaKind.video);
    expect(
      post.items.single.variants.single.url,
      'https://video.fbkk2-8.fna.fbcdn.net/reel.mp4?x=1&y=2',
    );
    expect(post.items.single.variants.single.label, '1080×1920');
    expect(
      post.items.single.thumbnailUrl,
      'https://scontent.fbkk22-1.fna.fbcdn.net/cover.jpg?x=1&y=2',
    );
    final storyPages = FacebookParser().pagesFor(
      Uri.parse(
        'https://www.facebook.com/stories/1388094934634575/UzpfSVNDOjE0NTY1MTQxMDk5NjQ3NDc=/',
      ),
    );
    expect(storyPages, hasLength(2));
    expect(storyPages.every((page) => !page.path.contains('plugins')), isTrue);
  });

  test('facebook album keeps each photo and the larger file', () {
    const html = '''
      <meta property="og:title" content="อัลบั้ม" />
      <meta property="og:image" content="https://scontent.a.fbcdn.net/v/t39.30808-6/1_111111111111_9_n.jpg?stp=cp0_dst-jpg_e15_fr_q65" />
      <img src="https://scontent.b.fbcdn.net/v/t39.30808-6/1_111111111111_9_n.jpg?stp=dst-webp_q70_s173x172" />
      <img src="https://scontent.c.fbcdn.net/v/t39.30808-6/2_222222222222_9_n.jpg?stp=dst-webp_q70_s173x172" />
      <img src="https://scontent.c.fbcdn.net/v/t39.30808-1/3_333333333333_9_n.jpg?stp=s40x40" />
    ''';
    final post = FacebookParser().parse(
      html,
      Uri.parse('https://www.facebook.com/share/abc/'),
    );
    expect(post, isNotNull);
    expect(post!.items, hasLength(2));
    expect(post.items.first.kind, MediaKind.image);
    expect(post.items.first.variants.single.url, contains('e15_fr'));
    expect(post.items.last.variants.single.url, contains('222222222222'));
  });

  test('facebook share stub points at the full page', () {
    const html = r'''
      <script>window.location.replace("https:\/\/www.facebook.com\/share\/abc\/?hpir=1");</script>
    ''';
    expect(
      FacebookParser().redirectTarget(html).toString(),
      'https://www.facebook.com/share/abc/?hpir=1',
    );
    expect(
      FacebookParser().postId('"story_fbid":"5000" "story_fbid":"5000"'),
      '5000',
    );
    expect(
      FacebookParser().belongsToStory(
        '"story_fbid":"1000" "story_fbid":"5000"',
        '5000',
      ),
      isTrue,
    );
    expect(
      FacebookParser().belongsToStory('"story_fbid":"8888"', '5000'),
      isFalse,
    );
    expect(
      FacebookParser().photoIds(
        r'(dkc \"photo_fbid\") (dkc \"1000\") (dkc "photo_fbid") (dkc "1000") (dkc "photo_fbid") (dkc "1006")',
      ),
      ['1000', '1006'],
    );
    expect(
      FacebookParser().linkedPhotoIds(
        '{&quot;direction&quot;:&quot;next&quot;,&quot;target_photo_id&quot;:&quot;1003&quot;}',
      ),
      ['1003'],
    );
  });

  test('facebook login wall is not treated as media', () {
    const html = '''
      <meta property="og:url" content="https://www.facebook.com/login/" />
      <meta property="og:title" content="Log in to Facebook" />
      <meta property="og:image" content="https://www.facebook.com/logo.png" />
    ''';
    expect(
      FacebookParser().parse(
        html,
        Uri.parse('https://www.facebook.com/login/'),
      ),
      isNull,
    );
  });

  test('vk sorts video qualities from high to low', () {
    const html = '''
      "url360":"https:\\/\\/vkuservideo.net\\/clip360.mp4"
      "url720":"https:\\/\\/vkuservideo.net\\/clip720.mp4"
    ''';
    final post = VkParser().parse(html, Uri.parse('https://vk.com/video-1_2'));
    expect(post, isNotNull);
    expect(post!.items.single.variants.map((variant) => variant.label), [
      '720p',
      '360p',
    ]);
    expect(
      VkParser()
          .pagesFor(Uri.parse('https://vk.com/video-10_20'))
          .first
          .queryParameters['oid'],
      '-10',
    );
  });

  test('vk keeps the opened video instead of the whole feed', () {
    const html = '''
      "id":111,"url360":"https://vkuservideo.net/other360.mp4","url720":"https://vkuservideo.net/other720.mp4"
      "id":456241127,"mp4_1080":"https://vkuservideo.net/main1080.mp4","mp4_720":"https://vkuservideo.net/main720.mp4"
    ''';
    final post = VkParser().parse(
      html,
      Uri.parse('https://m.vkvideo.ru/video-221115151_456241127'),
    );
    expect(post, isNotNull);
    expect(post!.items, hasLength(1));
    expect(post.items.single.variants.map((variant) => variant.label), [
      '1080p',
      '720p',
    ]);
    expect(post.items.single.variants.first.url, contains('main1080'));
  });
}
