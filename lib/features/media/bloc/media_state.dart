import 'package:equatable/equatable.dart';
import 'package:loading/features/media/model/download_progress.dart';
import 'package:loading/features/media/model/resolved_post.dart';

enum MediaPhase { idle, resolving, ready, downloading }

class MediaState extends Equatable {
  const MediaState({
    this.phase = MediaPhase.idle,
    this.post,
    this.selectedIds = const [],
    this.errorMessage,
    this.successMessage,
    this.progress,
  });

  final MediaPhase phase;
  final ResolvedPost? post;
  final List<String> selectedIds;
  final String? errorMessage;
  final String? successMessage;
  final DownloadProgress? progress;

  bool get isBusy => phase == MediaPhase.resolving || phase == MediaPhase.downloading;

  int get selectedCount {
    final current = post;
    if (current == null) return 0;
    var count = 0;
    for (final item in current.items) {
      if (selectedIds.contains(item.id)) count += 1;
    }
    return count;
  }

  MediaState copyWith({
    MediaPhase? phase,
    ResolvedPost? post,
    bool clearPost = false,
    List<String>? selectedIds,
    String? errorMessage,
    bool clearError = false,
    String? successMessage,
    bool clearSuccess = false,
    DownloadProgress? progress,
    bool clearProgress = false,
  }) {
    return MediaState(
      phase: phase ?? this.phase,
      post: clearPost ? null : (post ?? this.post),
      selectedIds: selectedIds ?? this.selectedIds,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearSuccess ? null : (successMessage ?? this.successMessage),
      progress: clearProgress ? null : (progress ?? this.progress),
    );
  }

  @override
  List<Object?> get props => [
        phase,
        post,
        selectedIds,
        errorMessage,
        successMessage,
        progress,
      ];
}
