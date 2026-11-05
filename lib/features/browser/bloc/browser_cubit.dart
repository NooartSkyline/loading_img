import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loading/core/app_exception.dart';
import 'package:loading/features/browser/data/stream_saver.dart';
import 'package:loading/features/browser/model/found_stream.dart';
import 'package:loading/features/media/data/download_keep_alive.dart';
import 'package:loading/features/media/data/gallery_store.dart';

enum BrowserPhase { idle, downloading }

class BrowserState extends Equatable {
  const BrowserState({
    this.streams = const [],
    this.selectedId,
    this.userPicked = false,
    this.opened = false,
    this.phase = BrowserPhase.idle,
    this.progress,
    this.errorMessage,
    this.successMessage,
  });

  final List<FoundStream> streams;
  final String? selectedId;
  final bool userPicked;
  final bool opened;
  final BrowserPhase phase;
  final StreamProgress? progress;
  final String? errorMessage;
  final String? successMessage;

  bool get isBusy => phase == BrowserPhase.downloading;

  FoundStream? get selected {
    final id = selectedId;
    if (id == null) return null;
    for (final stream in streams) {
      if (stream.id == id) return stream;
    }
    return null;
  }

  BrowserState copyWith({
    List<FoundStream>? streams,
    String? selectedId,
    bool clearSelection = false,
    bool? userPicked,
    bool? opened,
    BrowserPhase? phase,
    StreamProgress? progress,
    bool clearProgress = false,
    String? errorMessage,
    bool clearError = false,
    String? successMessage,
    bool clearSuccess = false,
  }) {
    return BrowserState(
      streams: streams ?? this.streams,
      selectedId: clearSelection ? null : (selectedId ?? this.selectedId),
      userPicked: userPicked ?? this.userPicked,
      opened: opened ?? this.opened,
      phase: phase ?? this.phase,
      progress: clearProgress ? null : (progress ?? this.progress),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearSuccess
          ? null
          : (successMessage ?? this.successMessage),
    );
  }

  @override
  List<Object?> get props => [
    streams,
    selectedId,
    userPicked,
    opened,
    phase,
    progress,
    errorMessage,
    successMessage,
  ];
}

class BrowserCubit extends Cubit<BrowserState> {
  BrowserCubit(this._saver, this._gallery, {DownloadKeepAlive? keepAlive})
    : _keepAlive = keepAlive ?? DownloadKeepAlive(),
      super(const BrowserState());

  final StreamSaver _saver;
  final GalleryStore _gallery;
  final DownloadKeepAlive _keepAlive;
  final Set<String> _measured = {};
  final Map<String, String> _audioUrls = {};
  int _measureGeneration = 0;
  String? _page;
  String? _userAgent;
  String? _dashClip;
  CancelToken? _cancel;

  void openPage() {
    if (state.isBusy) return;
    _measureGeneration += 1;
    _measured.clear();
    _audioUrls.clear();
    _page = null;
    _dashClip = null;
    emit(
      state.copyWith(
        opened: true,
        streams: const [],
        clearSelection: true,
        userPicked: false,
        clearError: true,
        clearSuccess: true,
        clearProgress: true,
      ),
    );
  }

  void addResource(String raw, {String? page}) {
    final stream = foundStreamFromUrl(raw);
    if (stream == null || !_acceptClip(stream)) {
      return;
    }
    if (page != null && page.isNotEmpty) {
      _page = page;
    }
    if (stream.audioOnly) {
      _audioUrls[stream.identity] = stream.url;
      _applyAudio(stream.identity, stream.url);
      return;
    }
    final audio = _audioUrls[stream.identity];
    final next = audio == null ? stream : stream.withAudio(audio);
    final streams = addFoundStream(state.streams, next, page: _page);
    if (!_sameStreams(state.streams, streams)) {
      final kept =
          state.userPicked &&
          streams.any((item) => item.id == state.selectedId);
      emit(
        state.copyWith(
          streams: streams,
          selectedId: kept ? state.selectedId : streams.first.id,
          clearError: true,
        ),
      );
    }
    if (audio != null) {
      _applyAudio(stream.identity, audio);
    }
    _scheduleMeasure();
  }

  bool _acceptClip(FoundStream stream) {
    final clip = dashClipId(stream.url);
    if (clip == null) {
      return true;
    }
    _dashClip ??= clip;
    return clip == _dashClip;
  }

  void _applyAudio(String identity, String audioUrl) {
    var changed = false;
    final streams = <FoundStream>[];
    for (final stream in state.streams) {
      if (stream.identity == identity && stream.audioUrl != audioUrl) {
        changed = true;
        _measured.remove(stream.url);
        streams.add(stream.withAudio(audioUrl));
      } else {
        streams.add(stream);
      }
    }
    if (!changed) return;
    emit(state.copyWith(streams: streams));
    _scheduleMeasure();
  }

  void setUserAgent(String? userAgent) {
    final agent = userAgent?.trim();
    if (agent == null || agent.isEmpty || agent == _userAgent) return;
    _userAgent = agent;
    _measured.clear();
    _scheduleMeasure();
  }

  void _scheduleMeasure() {
    final generation = ++_measureGeneration;
    final referer = _page;
    if (referer == null || referer.isEmpty) return;
    unawaited(_measureAll(generation, referer));
  }

  Future<void> _measureAll(int generation, String referer) async {
    final selected = state.selected;
    final pending = <FoundStream>[
      ?selected,
      for (final stream in state.streams)
        if (stream.url != selected?.url) stream,
    ];
    for (final stream in pending) {
      if (generation != _measureGeneration || isClosed) return;
      if (stream.bytes != null || !_measured.add(stream.url)) continue;
      int? bytes;
      try {
        bytes = await _saver.measure(
          stream: stream,
          referer: referer,
          userAgent: _userAgent,
        );
      } on AppException {
        bytes = null;
      }
      if (generation != _measureGeneration || isClosed || bytes == null) {
        continue;
      }
      _applyBytes(stream.url, bytes);
    }
  }

  void _applyBytes(String url, int bytes) {
    var changed = false;
    final streams = <FoundStream>[];
    for (final stream in state.streams) {
      if (stream.url == url && stream.bytes != bytes) {
        changed = true;
        streams.add(stream.withBytes(bytes));
      } else {
        streams.add(stream);
      }
    }
    if (!changed) return;
    final selectedId = state.userPicked ? state.selectedId : _largest(streams);
    emit(state.copyWith(streams: streams, selectedId: selectedId));
  }

  String? _largest(List<FoundStream> streams) {
    FoundStream? best;
    for (final stream in streams) {
      final size = stream.bytes;
      if (size == null) continue;
      final current = best?.bytes;
      if (current == null || size > current) best = stream;
    }
    return best?.id ?? state.selectedId;
  }

  bool _sameStreams(List<FoundStream> left, List<FoundStream> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index].url != right[index].url) return false;
    }
    return true;
  }

  void select(String id) {
    if (state.isBusy) return;
    if (!state.streams.any((stream) => stream.id == id)) return;
    emit(
      state.copyWith(
        selectedId: id,
        userPicked: true,
        clearError: true,
        clearSuccess: true,
      ),
    );
  }

  void fail(String message) {
    emit(state.copyWith(errorMessage: message, clearSuccess: true));
  }

  Future<void> download({
    required String referer,
    String? cookie,
    String? userAgent,
  }) async {
    if (state.isBusy) return;
    final selected = state.selected;
    if (selected == null) {
      emit(
        state.copyWith(errorMessage: 'ยังไม่ได้เลือกสตรีม', clearSuccess: true),
      );
      return;
    }
    final token = CancelToken();
    _cancel = token;
    await _keepAlive.acquire();
    emit(
      state.copyWith(
        phase: BrowserPhase.downloading,
        clearError: true,
        clearSuccess: true,
        progress: const StreamProgress(done: 0, total: 0, label: 'กำลังเริ่ม'),
      ),
    );
    Directory? work;
    try {
      final file = await _saver.fetch(
        stream: selected,
        referer: referer,
        cookie: cookie,
        userAgent: userAgent,
        cancelToken: token,
        onProgress: (progress) {
          if (!isClosed) emit(state.copyWith(progress: progress));
        },
      );
      work = file.parent;
      await _gallery.save(file: file, kind: streamKind);
      if (isClosed) return;
      emit(
        state.copyWith(
          phase: BrowserPhase.idle,
          clearProgress: true,
          clearError: true,
          successMessage: 'บันทึกลงคลังภาพแล้ว',
        ),
      );
    } catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(
          phase: BrowserPhase.idle,
          clearProgress: true,
          clearSuccess: true,
          errorMessage: asAppException(error).message,
        ),
      );
    } finally {
      await _keepAlive.release();
      final directory = work;
      if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }

  void cancel() {
    final token = _cancel;
    if (token != null && !token.isCancelled) token.cancel('ยกเลิกการโหลดแล้ว');
  }

  @override
  Future<void> close() {
    cancel();
    return super.close();
  }
}
