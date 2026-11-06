import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loading/core/app_exception.dart';
import 'package:loading/features/media/bloc/media_bloc.dart';
import 'package:loading/features/media/bloc/media_event.dart';
import 'package:loading/features/media/bloc/media_state.dart';
import 'package:loading/features/media/data/instagram_api.dart';
import 'package:loading/features/media/data/instagram_parser.dart';
import 'package:loading/features/media/data/instagram_session.dart';
import 'package:loading/features/media/data/media_repository.dart';
import 'package:loading/features/media/data/page_client.dart';
import 'package:loading/features/media/model/download_progress.dart';
import 'package:loading/features/media/model/media_item.dart';
import 'package:loading/features/media/model/resolved_post.dart';
import 'package:loading/features/media/data/media_gateway.dart';

void main() {
  test('instagram shortcode becomes the media id', () {
    expect(InstagramParser.mediaIdOf('DfRHW-jk4YW'), '4022028307541493270');
  });

  test('session cookie must be named sessionid', () {
    expect(instagramSignedIn('sessionid=abc'), isTrue);
    expect(instagramSignedIn('notsessionid=abc'), isFalse);
    expect(instagramSignedIn(null), isFalse);
  });

  test('signed-in media info keeps every carousel file', () {
    final post = InstagramParser().postFromMediaInfo({
      'items': [
        {
          'caption': {'text': 'album'},
          'carousel_media': [
            {
              'pk': 1,
              'image_versions2': {
                'candidates': [
                  {'width': 320, 'url': 'https://cdn.example/a-small.jpg'},
                  {'width': 1080, 'url': 'https://cdn.example/a.jpg'},
                ],
              },
            },
            {
              'pk': 2,
              'image_versions2': {
                'candidates': [
                  {'width': 720, 'url': 'https://cdn.example/b.jpg'},
                ],
              },
              'video_versions': [
                {'width': 480, 'url': 'https://cdn.example/b-small.mp4'},
                {'width': 720, 'url': 'https://cdn.example/b.mp4'},
              ],
            },
          ],
        },
      ],
    }, Uri.parse('https://www.instagram.com/p/DfRHW-jk4YW/?img_index=2'));

    expect(post.items, hasLength(2));
    expect(post.items.first.selectedVariant.url, 'https://cdn.example/a.jpg');
    expect(post.items[1].selectedVariant.url, 'https://cdn.example/b.mp4');
    expect(post.initialSelectedIds, ['ig-video-2']);
  });

  test('a cover-only page asks for instagram login', () {
    final repository = MediaRepository(
      pages: _Pages(
        '<meta property="og:image" content="https://scontent.cdninstagram.com/v/a.jpg" />',
      ),
      session: _Session(null),
      instagramApi: _UnusedApi(),
    );

    expect(
      repository.resolve(
        'https://www.instagram.com/p/DfRHW-jk4YW/?img_index=5',
      ),
      throwsA(isA<InstagramLoginRequired>()),
    );
  });

  test('files already on the page do not ask for login', () async {
    final repository = MediaRepository(
      pages: _Pages(
        r'{"display_url":"https:\/\/cdninstagram.com\/v\/a.jpg","display_url":"https:\/\/cdninstagram.com\/v\/b.jpg"}',
      ),
      session: _Session(null),
      instagramApi: _UnusedApi(),
    );

    final post = await repository.resolve('https://www.instagram.com/p/abc/');

    expect(post.items, hasLength(2));
  });

  test('a saved session loads the album instead of the cover', () async {
    final page = Uri.parse(
      'https://www.instagram.com/p/DfRHW-jk4YW/?img_index=2',
    );
    final album = InstagramParser().postFromMediaInfo({
      'items': [
        {
          'carousel_media': [
            {
              'pk': 1,
              'image_versions2': {
                'candidates': [
                  {'width': 1, 'url': 'https://cdn.example/1.jpg'},
                ],
              },
            },
            {
              'pk': 2,
              'image_versions2': {
                'candidates': [
                  {'width': 1, 'url': 'https://cdn.example/2.jpg'},
                ],
              },
            },
          ],
        },
      ],
    }, page);
    final api = _FixedApi(album);
    final repository = MediaRepository(
      pages: _Pages(
        '<meta property="og:image" content="https://scontent.cdninstagram.com/v/a.jpg" />',
      ),
      session: _Session('sessionid=abc; csrftoken=csrf'),
      instagramApi: api,
    );

    final post = await repository.resolve(
      'https://www.instagram.com/p/DfRHW-jk4YW/?img_index=2',
    );

    expect(api.calls, 1);
    expect(post.items.map((item) => item.selectedVariant.url), [
      'https://cdn.example/1.jpg',
      'https://cdn.example/2.jpg',
    ]);
    expect(post.initialSelectedIds, ['ig-image-2']);
  });

  test('api login wall asks for instagram login', () {
    final dio = Dio();
    dio.httpClientAdapter = _JsonAdapter(
      '{"message":"login_required","status":"fail"}',
      200,
    );

    expect(
      DioInstagramApi(dio: dio).load(
        Uri.parse('https://www.instagram.com/p/DfRHW-jk4YW/'),
        cookie: 'sessionid=abc',
      ),
      throwsA(isA<InstagramLoginRequired>()),
    );
  });

  test('login required stays on screen as an action', () async {
    final bloc = MediaBloc(_LoginGateway());
    addTearDown(bloc.close);

    bloc.add(const ResolveRequested('https://www.instagram.com/p/abc/'));
    final state = await bloc.stream.firstWhere(
      (next) => next.needsInstagramLogin,
    );

    expect(state.phase, MediaPhase.idle);
    expect(state.post, isNull);
    expect(state.needsFacebookLogin, isFalse);
    expect(state.errorMessage, contains('ล็อกอิน Instagram'));
  });

  test('facebook login required stays on screen as an action', () async {
    final bloc = MediaBloc(_LoginGateway(facebook: true));
    addTearDown(bloc.close);

    bloc.add(const ResolveRequested('https://www.facebook.com/share/p/abc/'));
    final state = await bloc.stream.firstWhere(
      (next) => next.needsFacebookLogin,
    );

    expect(state.needsInstagramLogin, isFalse);
    expect(state.errorMessage, contains('ล็อกอิน Facebook'));
  });
}

class _Pages extends PageClient {
  _Pages(this.html);

  final String html;

  @override
  Future<String> getHtml(Uri uri, {String? cookie}) async => html;
}

class _Session implements InstagramSession {
  _Session(this.cookie);

  final String? cookie;

  @override
  Future<String?> cookieHeader() async => cookie;

  @override
  Future<void> forget() async {}
}

class _UnusedApi implements InstagramApi {
  @override
  Future<ResolvedPost> load(Uri page, {required String cookie}) {
    throw StateError('api should not be called');
  }
}

class _FixedApi implements InstagramApi {
  _FixedApi(this.post);

  final ResolvedPost post;
  var calls = 0;

  @override
  Future<ResolvedPost> load(Uri page, {required String cookie}) async {
    calls += 1;
    return post;
  }
}

class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.body, this.status);

  final String body;
  final int status;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _LoginGateway implements MediaGateway {
  _LoginGateway({this.facebook = false});

  final bool facebook;

  @override
  Future<ResolvedPost> resolve(String url) async {
    if (facebook) throw const FacebookLoginRequired();
    throw const InstagramLoginRequired();
  }

  @override
  Future<int?> fileSize(String url, {required String referer}) async => null;

  @override
  Stream<DownloadProgress> download(
    List<MediaItem> items, {
    required String referer,
  }) {
    return const Stream.empty();
  }

  @override
  void cancelDownload() {}
}
