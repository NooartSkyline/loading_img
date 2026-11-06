import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:loading/core/app_exception.dart';
import 'package:loading/core/format_bytes.dart';
import 'package:loading/features/media/data/download_keep_alive.dart';
import 'package:loading/features/media/data/embedded_text.dart';
import 'package:loading/features/media/data/facebook_parser.dart';
import 'package:loading/features/media/data/facebook_session.dart';
import 'package:loading/features/media/data/file_downloader.dart';
import 'package:loading/features/media/data/gallery_store.dart';
import 'package:loading/features/media/data/instagram_api.dart';
import 'package:loading/features/media/data/instagram_parser.dart';
import 'package:loading/features/media/data/instagram_session.dart';
import 'package:loading/features/media/data/media_gateway.dart';
import 'package:loading/features/media/data/page_client.dart';
import 'package:loading/features/media/data/platform_detector.dart';
import 'package:loading/features/media/data/vk_parser.dart';
import 'package:loading/features/media/model/download_progress.dart';
import 'package:loading/features/media/model/media_item.dart';
import 'package:loading/features/media/model/media_kind.dart';
import 'package:loading/features/media/model/media_variant.dart';
import 'package:loading/features/media/model/resolved_post.dart';
import 'package:path_provider/path_provider.dart';

class MediaRepository implements MediaGateway {
  MediaRepository({
    PageClient? pages,
    FileDownloader? downloader,
    GalleryStore? gallery,
    InstagramParser? instagram,
    InstagramSession? session,
    this.instagramApi,
    FacebookParser? facebook,
    FacebookSession? facebookSession,
    VkParser? vk,
    DownloadKeepAlive? keepAlive,
    Future<Directory> Function()? workDirectory,
  }) : _pages = pages ?? PageClient(),
       _downloader = downloader ?? FileDownloader(),
       _gallery = gallery ?? const GalleryStore(),
       _instagram = instagram ?? InstagramParser(),
       _session = session ?? const WebViewInstagramSession(),
       _facebook = facebook ?? FacebookParser(),
       _facebookSession = facebookSession ?? const WebViewFacebookSession(),
       _vk = vk ?? VkParser(),
       _keepAlive = keepAlive ?? DownloadKeepAlive(),
       _workDirectory = workDirectory ?? getTemporaryDirectory;

  final PageClient _pages;
  final FileDownloader _downloader;
  final GalleryStore _gallery;
  final InstagramParser _instagram;
  final InstagramSession _session;
  final InstagramApi? instagramApi;
  InstagramApi? _ownedApi;
  final FacebookParser _facebook;
  final FacebookSession _facebookSession;
  final VkParser _vk;
  final DownloadKeepAlive _keepAlive;
  final Future<Directory> Function() _workDirectory;
  CancelToken? _cancel;

  @override
  void cancelDownload() {
    final token = _cancel;
    if (token != null && !token.isCancelled) {
      token.cancel('ยกเลิกการโหลดแล้ว');
    }
  }

  @override
  Future<int?> fileSize(String url, {required String referer}) async {
    final info = await _downloader.probe(url: url, referer: referer);
    final bytes = info.totalBytes;
    if (bytes == null || bytes <= 0) return null;
    return bytes;
  }

  @override
  Future<ResolvedPost> resolve(String raw) async {
    final uri = parseUserUrl(raw);
    switch (detectPlatform(uri)) {
      case MediaPlatform.instagram:
        return _instagramPost(uri);
      case MediaPlatform.facebook:
        return _facebookPost(uri);
      case MediaPlatform.vk:
        return _paged(
          uri,
          pages: _vk.pagesFor(uri),
          parse: _vk.parse,
          emptyMessage: 'ไม่พบรูปหรือวิดีโอในหน้า VK นี้ ลิงก์อาจไม่สาธารณะ',
        );
      case MediaPlatform.direct:
        return _filePost(uri, unknownPage: false);
      case MediaPlatform.unknown:
        return _filePost(uri, unknownPage: true);
    }
  }

  Future<ResolvedPost> _instagramPost(Uri uri) async {
    _rejectStory(uri);
    var target = uri;
    if (InstagramParser.shortcodeOf(target) == null) {
      target = await _pages.resolveRedirect(uri);
    }
    _rejectStory(target);
    if (InstagramParser.shortcodeOf(target) == null) {
      throw const AppException('ลิงก์ Instagram ไม่ใช่โพสต์หรือรีล');
    }
    final cookie = await _session.cookieHeader();
    AppException? apiError;
    if (instagramSignedIn(cookie)) {
      try {
        return await _api.load(target, cookie: cookie!);
      } on InstagramLoginRequired catch (error) {
        await _session.forget();
        apiError = error;
      } on AppException catch (error) {
        apiError = error;
      }
    }
    final pages = InstagramParser.pagesFor(target);
    for (final page in pages) {
      try {
        final html = await _pages.getHtml(page);
        final parsed = _instagram.read(html, target);
        if (parsed.coverOnly) {
          throw apiError ?? const InstagramLoginRequired();
        }
        return parsed.post;
      } on InstagramLoginRequired {
        rethrow;
      } on AppException {
        continue;
      }
    }
    if (apiError != null) throw apiError;
    throw const InstagramLoginRequired();
  }

  InstagramApi get _api =>
      instagramApi ?? (_ownedApi ??= DioInstagramApi(parser: _instagram));

  void _rejectStory(Uri uri) {
    if (uri.path.toLowerCase().contains('/stories/')) {
      throw const AppException(
        'สตอรี่ที่ต้องล็อกอินยังดึงไม่ได้ ใช้ลิงก์โพสต์หรือรีลสาธารณะ',
      );
    }
  }

  Future<ResolvedPost> _facebookPost(Uri uri) async {
    final story = uri.path.toLowerCase().contains('/stories/');
    final cookie = await _facebookSession.cookieHeader();
    final signedIn = facebookSignedIn(cookie);
    final open = await _facebookPages(uri, cookie: null);
    if (open.post != null) return open.post!;
    if (signedIn) {
      final authed = await _facebookPages(uri, cookie: cookie);
      if (authed.post != null) return authed.post!;
      if (authed.loginWall) {
        await _facebookSession.forget();
        throw const FacebookLoginRequired();
      }
      if (authed.sawPage || open.sawPage) {
        throw AppException(
          story
              ? 'สตอรี่นี้ Facebook ไม่ได้ใส่ไฟล์ให้เปิดนอกแอป'
              : 'ไม่พบรูปหรือวิดีโอในหน้า Facebook นี้ ลิงก์อาจไม่สาธารณะ',
        );
      }
      throw authed.error ??
          open.error ??
          const AppException('ดึงข้อมูลจากลิงก์นี้ไม่สำเร็จ');
    }
    if (open.sawPage && !story) throw const FacebookLoginRequired();
    if (open.sawPage) {
      throw const AppException('สตอรี่นี้ Facebook ไม่ได้ใส่ไฟล์ให้เปิดนอกแอป');
    }
    throw open.error ?? const AppException('ดึงข้อมูลจากลิงก์นี้ไม่สำเร็จ');
  }

  Future<
    ({ResolvedPost? post, bool sawPage, bool loginWall, AppException? error})
  >
  _facebookPages(Uri uri, {required String? cookie}) async {
    final queue = List<Uri>.of(_facebook.pagesFor(uri));
    final tried = <String>{};
    AppException? lastError;
    var sawPage = false;
    String? stubHtml;
    final stills = <String, String>{};
    final order = <String>[];
    final ids = <String>[];
    final seenIds = <String>{};
    String? title;
    String? story;
    var storyScore = -1;
    var loginWall = false;
    while (queue.isNotEmpty) {
      final page = queue.removeAt(0);
      if (!tried.add(page.toString())) continue;
      try {
        final html = await _pages.getHtml(page, cookie: cookie);
        sawPage = true;
        final next = _facebook.redirectTarget(html);
        if (next != null && !tried.contains(next.toString())) {
          stubHtml = html;
          queue.insert(0, next);
          continue;
        }
        final parsed = _facebook.parse(html, uri);
        if (parsed == null) {
          if (_facebook.isLoginWall(html)) loginWall = true;
          continue;
        }
        if (parsed.items.any((item) => item.kind == MediaKind.video)) {
          return (post: parsed, sawPage: true, loginWall: false, error: null);
        }
        final pageIds = _facebook.photoIds(html);
        final pageStory = _facebook.postId(html);
        if (pageStory != null && pageIds.length > storyScore) {
          story = pageStory;
          storyScore = pageIds.length;
        }
        for (final id in pageIds) {
          if (seenIds.add(id)) ids.add(id);
        }
        if (title == null || pageIds.isNotEmpty) {
          title = parsed.title ?? title;
        }
        for (final item in parsed.items) {
          final url = item.variants.first.url;
          final key = _facebook.fileId(url) ?? url;
          final current = stills[key];
          if (current == null) {
            stills[key] = url;
            order.add(key);
            continue;
          }
          if (_facebook.fileRank(url) > _facebook.fileRank(current)) {
            stills[key] = url;
          }
        }
      } on AppException catch (error) {
        lastError = error;
      }
    }
    if (order.isNotEmpty || ids.isNotEmpty) {
      final collected = _facebookImages(
        source: uri,
        title: title,
        urls: [for (final key in order) stills[key]!],
      );
      final post = ids.isEmpty
          ? collected
          : await _facebookAlbum(collected, ids, story, cookie);
      if (post.items.isNotEmpty) {
        return (post: post, sawPage: true, loginWall: false, error: null);
      }
    }
    if (stubHtml != null) {
      final parsed = _facebook.parse(stubHtml, uri);
      if (parsed != null) {
        return (post: parsed, sawPage: true, loginWall: false, error: null);
      }
    }
    return (
      post: null,
      sawPage: sawPage,
      loginWall: loginWall,
      error: lastError,
    );
  }

  ResolvedPost _facebookImages({
    required Uri source,
    required String? title,
    required List<String> urls,
  }) {
    return ResolvedPost(
      sourceUrl: source.toString(),
      referer: 'https://www.facebook.com/',
      platformLabel: 'Facebook',
      title: title,
      items: [
        for (var i = 0; i < urls.length; i++)
          MediaItem(
            id: 'fb-image-$i',
            kind: MediaKind.image,
            title: title,
            thumbnailUrl: urls[i],
            variants: [
              MediaVariant(id: 'file', label: 'ต้นฉบับ', url: urls[i]),
            ],
          ),
      ],
    );
  }

  Future<ResolvedPost> _facebookAlbum(
    ResolvedPost parsed,
    List<String> known,
    String? story,
    String? cookie,
  ) async {
    if (parsed.items.any((item) => item.kind == MediaKind.video)) return parsed;
    if (known.isEmpty) return parsed;
    final queue = List<String>.of(known);
    final seen = <String>{};
    final items = <MediaItem>[];
    while (queue.isNotEmpty && items.length < 40 && seen.length < 40) {
      final wave = <String>[];
      while (queue.isNotEmpty && wave.length < 4) {
        final id = queue.removeAt(0);
        if (seen.add(id)) wave.add(id);
      }
      if (wave.isEmpty) break;
      final pages = await Future.wait([
        for (final id in wave)
          _pages.getHtml(
            _facebook.photoPage(id, expanded: story != null),
            cookie: cookie,
          ),
      ]);
      for (final page in pages) {
        final inStory = story == null || _facebook.belongsToStory(page, story);
        if (!inStory) continue;
        if (items.length < 40) {
          final url = _facebook.photoFile(page);
          if (url != null) {
            items.add(
              MediaItem(
                id: 'fb-image-${items.length}',
                kind: MediaKind.image,
                title: parsed.title,
                thumbnailUrl: url,
                variants: [
                  MediaVariant(id: 'file', label: 'ต้นฉบับ', url: url),
                ],
              ),
            );
          }
        }
        if (story == null) continue;
        for (final linked in _facebook.linkedPhotoIds(page)) {
          if (!seen.contains(linked)) queue.add(linked);
        }
      }
    }
    if (items.isEmpty) return parsed;
    return parsed.copyWith(items: _mergePhotos(parsed, items));
  }

  List<MediaItem> _mergePhotos(ResolvedPost parsed, List<MediaItem> opened) {
    final urls = <String>[];
    final seen = <String>{};
    void add(String url) {
      final key = _facebook.fileId(url) ?? url;
      if (!seen.add(key)) return;
      urls.add(url);
    }

    for (final item in opened) {
      add(item.variants.first.url);
    }
    for (final item in parsed.items) {
      if (item.kind != MediaKind.image) continue;
      add(item.variants.first.url);
    }
    return [
      for (var i = 0; i < urls.length; i++)
        MediaItem(
          id: 'fb-image-$i',
          kind: MediaKind.image,
          title: parsed.title,
          thumbnailUrl: urls[i],
          variants: [MediaVariant(id: 'file', label: 'ต้นฉบับ', url: urls[i])],
        ),
    ];
  }

  Future<ResolvedPost> _paged(
    Uri source, {
    required List<Uri> pages,
    required ResolvedPost? Function(String html, Uri source) parse,
    required String emptyMessage,
  }) async {
    AppException? lastError;
    var sawPage = false;
    for (final page in pages) {
      try {
        final html = await _pages.getHtml(page);
        sawPage = true;
        final parsed = parse(html, source);
        if (parsed != null) return parsed;
      } on AppException catch (error) {
        lastError = error;
      }
    }
    if (sawPage) throw AppException(emptyMessage);
    throw lastError ?? const AppException('ดึงข้อมูลจากลิงก์นี้ไม่สำเร็จ');
  }

  Future<ResolvedPost> _filePost(Uri uri, {required bool unknownPage}) async {
    final referer = uri.origin;
    final info = await _downloader.probe(url: uri.toString(), referer: referer);
    final hint = kindFromType(info.contentType, uri);
    if (hint == null) {
      throw AppException(
        unknownPage
            ? 'รองรับลิงก์ Instagram, Facebook, VK หรือไฟล์รูปและวิดีโอโดยตรง'
            : 'ลิงก์นี้ไม่ใช่ไฟล์รูปหรือวิดีโอ',
      );
    }
    final kind = hint == FileKindHint.video ? MediaKind.video : MediaKind.image;
    final bytes = info.totalBytes;
    final label = bytes == null ? 'ต้นฉบับ' : 'ต้นฉบับ · ${formatBytes(bytes)}';
    final name = uri.pathSegments.isEmpty ? null : uri.pathSegments.last;
    return ResolvedPost(
      sourceUrl: uri.toString(),
      referer: referer,
      platformLabel: 'ไฟล์ตรง',
      title: name,
      items: [
        MediaItem(
          id: 'file-0',
          kind: kind,
          title: name,
          thumbnailUrl: kind == MediaKind.image ? uri.toString() : null,
          variants: [
            MediaVariant(id: 'file', label: label, url: uri.toString()),
          ],
        ),
      ],
    );
  }

  @override
  Stream<DownloadProgress> download(
    List<MediaItem> items, {
    required String referer,
  }) {
    cancelDownload();
    final token = CancelToken();
    _cancel = token;
    final controller = StreamController<DownloadProgress>();
    unawaited(_downloadAll(controller, items, referer, token));
    return controller.stream;
  }

  Future<void> _downloadAll(
    StreamController<DownloadProgress> controller,
    List<MediaItem> items,
    String referer,
    CancelToken token,
  ) async {
    Directory? work;
    var saved = 0;
    await _keepAlive.acquire();
    try {
      if (items.isEmpty) throw const AppException('ยังไม่ได้เลือกไฟล์');
      final root = await _workDirectory();
      work = Directory(
        '${root.path}/loading_${DateTime.now().microsecondsSinceEpoch}',
      );
      await work.create(recursive: true);
      for (var index = 0; index < items.length; index++) {
        if (token.isCancelled) {
          throw AppException(_cancelMessage(saved));
        }
        final item = items[index];
        final variant = item.selectedVariant;
        final info = await _downloader.probe(
          url: variant.url,
          referer: referer,
          cancelToken: token,
        );
        final ext = fileExtension(
          url: variant.url,
          contentType: info.contentType,
          video: item.kind == MediaKind.video,
        );
        final name = safeFileName('${item.id}_${variant.id}.$ext');
        var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
        final file = await _downloader.download(
          url: variant.url,
          directory: work,
          fileName: name,
          referer: referer,
          known: info,
          cancelToken: token,
          onProgress: (part) {
            final now = DateTime.now();
            final force =
                part.merging ||
                (part.bytesTotal > 0 && part.bytesDone >= part.bytesTotal);
            if (!force &&
                now.difference(lastEmit) < const Duration(milliseconds: 200)) {
              return;
            }
            lastEmit = now;
            _add(
              controller,
              DownloadProgress(
                itemIndex: index,
                itemCount: items.length,
                partIndex: part.partIndex,
                partCount: part.partCount,
                bytesDone: part.bytesDone,
                bytesTotal: part.bytesTotal,
                step: part.merging
                    ? DownloadStep.merging
                    : DownloadStep.fetching,
                savedCount: saved,
              ),
            );
          },
        );
        _add(
          controller,
          DownloadProgress(
            itemIndex: index,
            itemCount: items.length,
            partIndex: 0,
            partCount: 1,
            bytesDone: 1,
            bytesTotal: 1,
            step: DownloadStep.saving,
            savedCount: saved,
          ),
        );
        await _gallery.save(file: file, kind: item.kind);
        saved += 1;
        _add(
          controller,
          DownloadProgress(
            itemIndex: index,
            itemCount: items.length,
            partIndex: 0,
            partCount: 1,
            bytesDone: 1,
            bytesTotal: 1,
            step: DownloadStep.saving,
            savedCount: saved,
          ),
        );
      }
    } catch (error, stack) {
      final failure = asAppException(error);
      final message = failure.message == 'ยกเลิกการโหลดแล้ว'
          ? _cancelMessage(saved)
          : saved > 0
          ? '${failure.message} (บันทึกไปแล้ว $saved ไฟล์)'
          : failure.message;
      _addError(controller, AppException(message), stack);
    } finally {
      await _keepAlive.release();
      final directory = work;
      if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
      if (!controller.isClosed) await controller.close();
    }
  }

  String _cancelMessage(int saved) {
    if (saved <= 0) return 'ยกเลิกการโหลดแล้ว';
    return 'ยกเลิกแล้ว บันทึกไปแล้ว $saved ไฟล์';
  }

  void _add(
    StreamController<DownloadProgress> controller,
    DownloadProgress progress,
  ) {
    if (!controller.isClosed) controller.add(progress);
  }

  void _addError(
    StreamController<DownloadProgress> controller,
    Object error,
    StackTrace stack,
  ) {
    if (!controller.isClosed) controller.addError(error, stack);
  }
}
