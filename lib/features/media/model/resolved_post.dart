import 'package:equatable/equatable.dart';
import 'package:loading/features/media/model/media_item.dart';

class ResolvedPost extends Equatable {
  const ResolvedPost({
    required this.sourceUrl,
    required this.referer,
    required this.platformLabel,
    required this.items,
    this.title,
    this.initialSelectedIds = const [],
  });

  final String sourceUrl;
  final String referer;
  final String platformLabel;
  final String? title;
  final List<MediaItem> items;
  final List<String> initialSelectedIds;

  ResolvedPost copyWith({List<MediaItem>? items}) {
    return ResolvedPost(
      sourceUrl: sourceUrl,
      referer: referer,
      platformLabel: platformLabel,
      title: title,
      items: items ?? this.items,
      initialSelectedIds: initialSelectedIds,
    );
  }

  @override
  List<Object?> get props => [
        sourceUrl,
        referer,
        platformLabel,
        title,
        items,
        initialSelectedIds,
      ];
}
