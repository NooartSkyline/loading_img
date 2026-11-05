import 'package:flutter_test/flutter_test.dart';
import 'package:loading/core/app_exception.dart';
import 'package:loading/features/media/bloc/media_bloc.dart';
import 'package:loading/features/media/bloc/media_event.dart';
import 'package:loading/features/media/bloc/media_state.dart';
import 'package:loading/features/media/data/media_gateway.dart';
import 'package:loading/features/media/model/download_progress.dart';
import 'package:loading/features/media/model/media_item.dart';
import 'package:loading/features/media/model/media_kind.dart';
import 'package:loading/features/media/model/media_variant.dart';
import 'package:loading/features/media/model/resolved_post.dart';

void main() {
  test('blank link does not call the resolver', () async {
    final gateway = _FakeGateway();
    final bloc = MediaBloc(gateway);
    addTearDown(bloc.close);

    bloc.add(const ResolveRequested('   '));
    final state = await bloc.stream.first;

    expect(state.errorMessage, 'ใส่ลิงก์ก่อน');
    expect(gateway.resolveCalls, 0);
  });

  test('resolve failure stays visible', () async {
    final gateway = _FakeGateway(error: const AppException('โพสต์นี้ไม่สาธารณะ'));
    final bloc = MediaBloc(gateway);
    addTearDown(bloc.close);

    bloc.add(const ResolveRequested('https://www.instagram.com/p/abc/'));
    final state = await bloc.stream.firstWhere(
      (next) => next.phase == MediaPhase.idle && next.errorMessage != null,
    );

    expect(state.errorMessage, 'โพสต์นี้ไม่สาธารณะ');
    expect(state.post, isNull);
  });

  test('empty selection does not start a download', () async {
    final gateway = _FakeGateway(post: _post());
    final bloc = MediaBloc(gateway);
    addTearDown(bloc.close);

    bloc.add(const ResolveRequested('https://vk.com/video-1_2'));
    await bloc.stream.firstWhere((state) => state.phase == MediaPhase.ready);
    bloc.add(const SelectionSet(false));
    await bloc.stream.firstWhere((state) => state.selectedIds.isEmpty);
    bloc.add(const DownloadRequested());
    final state = await bloc.stream.firstWhere(
      (next) => next.errorMessage == 'ยังไม่ได้เลือกไฟล์',
    );

    expect(state.phase, MediaPhase.ready);
    expect(gateway.downloadCalls, 0);
  });

  test('finished download reports how many files were saved', () async {
    final gateway = _FakeGateway(post: _post());
    final bloc = MediaBloc(gateway);
    addTearDown(bloc.close);

    bloc.add(const ResolveRequested('https://vk.com/video-1_2'));
    await bloc.stream.firstWhere((state) => state.phase == MediaPhase.ready);
    bloc.add(const DownloadRequested());
    final state = await bloc.stream.firstWhere((next) => next.successMessage != null);

    expect(state.successMessage, 'บันทึกลงคลังภาพแล้ว 1 ไฟล์');
    expect(state.phase, MediaPhase.ready);
    expect(gateway.downloadCalls, 1);
  });

  test('a linked slide starts selected', () async {
    final gateway = _FakeGateway(
      post: _post(
        extraId: 'ig-image-3',
        initialSelectedIds: const ['ig-image-3'],
      ),
    );
    final bloc = MediaBloc(gateway);
    addTearDown(bloc.close);

    bloc.add(const ResolveRequested('https://www.instagram.com/p/DfUJ3lZExVL/?img_index=4'));
    final state = await bloc.stream.firstWhere((next) => next.phase == MediaPhase.ready);

    expect(state.selectedIds, ['ig-image-3']);
    expect(state.post?.items, hasLength(2));
  });
}

ResolvedPost _post({String? extraId, List<String> initialSelectedIds = const []}) {
  return ResolvedPost(
    sourceUrl: 'https://vk.com/video-1_2',
    referer: 'https://vk.com/',
    platformLabel: 'VK',
    initialSelectedIds: initialSelectedIds,
    items: [
      MediaItem(
        id: 'vk-video-0',
        kind: MediaKind.video,
        variants: const [
          MediaVariant(id: 'q0', label: '720p', url: 'https://cdn.example/a.mp4'),
        ],
      ),
      if (extraId != null)
        MediaItem(
          id: extraId,
          kind: MediaKind.image,
          variants: const [
            MediaVariant(id: 'file', label: 'ต้นฉบับ', url: 'https://cdn.example/b.jpg'),
          ],
        ),
    ],
  );
}

class _FakeGateway implements MediaGateway {
  _FakeGateway({this.post, this.error});

  final ResolvedPost? post;
  final AppException? error;
  int resolveCalls = 0;
  int downloadCalls = 0;

  @override
  Future<ResolvedPost> resolve(String url) async {
    resolveCalls += 1;
    final failure = error;
    if (failure != null) throw failure;
    final resolved = post;
    if (resolved == null) throw const AppException('ไม่มีโพสต์');
    return resolved;
  }

  @override
  Future<int?> fileSize(String url, {required String referer}) async => null;

  @override
  Stream<DownloadProgress> download(
    List<MediaItem> items, {
    required String referer,
  }) async* {
    downloadCalls += 1;
    yield DownloadProgress(
      itemIndex: 0,
      itemCount: items.length,
      partIndex: 0,
      partCount: 1,
      bytesDone: 1,
      bytesTotal: 1,
      step: DownloadStep.saving,
      savedCount: items.length,
    );
  }

  @override
  void cancelDownload() {}
}
