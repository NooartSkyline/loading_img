import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loading/core/app_exception.dart';
import 'package:loading/features/media/bloc/media_event.dart';
import 'package:loading/features/media/bloc/media_state.dart';
import 'package:loading/features/media/data/media_gateway.dart';
import 'package:loading/features/media/model/download_progress.dart';
import 'package:loading/features/media/model/media_item.dart';
import 'package:loading/features/media/model/resolved_post.dart';

class MediaBloc extends Bloc<MediaEvent, MediaState> {
  MediaBloc(this._gateway) : super(const MediaState()) {
    on<ResolveRequested>(_onResolve);
    on<SelectionToggled>(_onToggle);
    on<SelectionSet>(_onSet);
    on<VariantChosen>(_onVariant);
    on<DownloadRequested>(_onDownload);
    on<DownloadCancelled>(_onCancel);
    on<NoticeRequested>(_onNotice);
    on<VariantMeasured>(_onMeasured);
  }

  final MediaGateway _gateway;

  Future<void> _onResolve(
    ResolveRequested event,
    Emitter<MediaState> emit,
  ) async {
    if (state.isBusy) return;
    final url = event.url.trim();
    if (url.isEmpty) {
      emit(state.copyWith(errorMessage: 'ใส่ลิงก์ก่อน', clearSuccess: true));
      return;
    }
    emit(
      state.copyWith(
        phase: MediaPhase.resolving,
        clearPost: true,
        selectedIds: const [],
        clearError: true,
        clearSuccess: true,
        clearProgress: true,
        clearInstagramLogin: true,
        clearFacebookLogin: true,
      ),
    );
    try {
      final post = await _gateway.resolve(url);
      if (emit.isDone) return;
      if (post.items.isEmpty) {
        emit(
          state.copyWith(
            phase: MediaPhase.idle,
            clearPost: true,
            errorMessage: 'ไม่พบรูปหรือวิดีโอในลิงก์นี้',
            clearSuccess: true,
          ),
        );
        return;
      }
      emit(
        state.copyWith(
          phase: MediaPhase.ready,
          post: post,
          selectedIds: _initialSelection(post),
          clearError: true,
          clearSuccess: true,
          clearProgress: true,
          clearInstagramLogin: true,
          clearFacebookLogin: true,
        ),
      );
      unawaited(_attachSizes(post));
    } catch (error) {
      if (emit.isDone) return;
      final appError = asAppException(error);
      final needsInstagram = appError is InstagramLoginRequired;
      final needsFacebook = appError is FacebookLoginRequired;
      emit(
        state.copyWith(
          phase: MediaPhase.idle,
          clearPost: true,
          selectedIds: const [],
          clearProgress: true,
          clearSuccess: true,
          errorMessage: appError.message,
          needsInstagramLogin: needsInstagram,
          clearInstagramLogin: !needsInstagram,
          needsFacebookLogin: needsFacebook,
          clearFacebookLogin: !needsFacebook,
        ),
      );
    }
  }

  Future<void> _attachSizes(ResolvedPost post) async {
    for (final item in post.items) {
      for (final variant in item.variants) {
        if (variant.bytes != null || variant.label.contains('·')) continue;
        int? bytes;
        try {
          bytes = await _gateway.fileSize(variant.url, referer: post.referer);
        } on AppException {
          continue;
        }
        if (isClosed || state.post?.sourceUrl != post.sourceUrl) return;
        final size = bytes;
        if (size == null) continue;
        add(
          VariantMeasured(
            sourceUrl: post.sourceUrl,
            itemId: item.id,
            variantId: variant.id,
            bytes: size,
          ),
        );
      }
    }
  }

  void _onMeasured(VariantMeasured event, Emitter<MediaState> emit) {
    final current = state.post;
    if (current == null || current.sourceUrl != event.sourceUrl) return;
    emit(
      state.copyWith(
        post: current.copyWith(
          items: [
            for (final entry in current.items)
              if (entry.id == event.itemId)
                entry.withSize(event.variantId, event.bytes)
              else
                entry,
          ],
        ),
      ),
    );
  }

  void _onToggle(SelectionToggled event, Emitter<MediaState> emit) {
    if (state.phase == MediaPhase.downloading || state.post == null) return;
    final selected = state.selectedIds.contains(event.itemId);
    final next = selected
        ? [
            for (final id in state.selectedIds)
              if (id != event.itemId) id,
          ]
        : [...state.selectedIds, event.itemId];
    emit(state.copyWith(selectedIds: next, clearError: true));
  }

  void _onSet(SelectionSet event, Emitter<MediaState> emit) {
    final post = state.post;
    if (state.phase == MediaPhase.downloading || post == null) return;
    emit(
      state.copyWith(
        selectedIds: event.selectAll
            ? [for (final item in post.items) item.id]
            : const [],
        clearError: true,
      ),
    );
  }

  void _onVariant(VariantChosen event, Emitter<MediaState> emit) {
    final post = state.post;
    if (state.phase == MediaPhase.downloading || post == null) return;
    MediaItem? target;
    for (final item in post.items) {
      if (item.id == event.itemId) target = item;
    }
    if (target == null) return;
    final known = target.variants.any(
      (variant) => variant.id == event.variantId,
    );
    if (!known) {
      emit(
        state.copyWith(
          errorMessage: 'ไม่พบความละเอียดที่เลือก',
          clearSuccess: true,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        post: post.copyWith(
          items: [
            for (final item in post.items)
              if (item.id == event.itemId)
                item.withVariant(event.variantId)
              else
                item,
          ],
        ),
        clearError: true,
      ),
    );
  }

  Future<void> _onDownload(
    DownloadRequested event,
    Emitter<MediaState> emit,
  ) async {
    final post = state.post;
    if (post == null || state.phase == MediaPhase.downloading) return;
    final items = [
      for (final item in post.items)
        if (state.selectedIds.contains(item.id)) item,
    ];
    if (items.isEmpty) {
      emit(
        state.copyWith(errorMessage: 'ยังไม่ได้เลือกไฟล์', clearSuccess: true),
      );
      return;
    }
    emit(
      state.copyWith(
        phase: MediaPhase.downloading,
        clearError: true,
        clearSuccess: true,
        clearProgress: true,
      ),
    );
    try {
      await emit.forEach<DownloadProgress>(
        _gateway.download(items, referer: post.referer),
        onData: (progress) => state.copyWith(
          phase: MediaPhase.downloading,
          progress: progress,
          clearError: true,
          clearSuccess: true,
        ),
      );
    } catch (error) {
      if (emit.isDone) return;
      emit(
        state.copyWith(
          phase: MediaPhase.ready,
          clearProgress: true,
          clearSuccess: true,
          errorMessage: asAppException(error).message,
        ),
      );
      return;
    }
    if (emit.isDone) return;
    final saved = state.progress?.savedCount ?? 0;
    if (saved <= 0) {
      emit(
        state.copyWith(
          phase: MediaPhase.ready,
          clearProgress: true,
          clearSuccess: true,
          errorMessage: 'ไม่มีไฟล์ถูกบันทึก',
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        phase: MediaPhase.ready,
        clearProgress: true,
        clearError: true,
        successMessage: 'บันทึกลงคลังภาพแล้ว $saved ไฟล์',
      ),
    );
  }

  void _onCancel(DownloadCancelled event, Emitter<MediaState> emit) {
    if (state.phase != MediaPhase.downloading) return;
    _gateway.cancelDownload();
  }

  void _onNotice(NoticeRequested event, Emitter<MediaState> emit) {
    final message = event.message.trim();
    if (message.isEmpty) return;
    emit(state.copyWith(errorMessage: message, clearSuccess: true));
  }

  List<String> _initialSelection(ResolvedPost post) {
    final preferred = [
      for (final id in post.initialSelectedIds)
        if (post.items.any((item) => item.id == id)) id,
    ];
    if (preferred.isNotEmpty) return preferred;
    return [for (final item in post.items) item.id];
  }

  @override
  Future<void> close() {
    _gateway.cancelDownload();
    return super.close();
  }
}
