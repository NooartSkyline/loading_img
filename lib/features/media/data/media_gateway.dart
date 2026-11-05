import 'package:loading/features/media/model/download_progress.dart';
import 'package:loading/features/media/model/media_item.dart';
import 'package:loading/features/media/model/resolved_post.dart';

abstract class MediaGateway {
  Future<ResolvedPost> resolve(String url);

  Future<int?> fileSize(String url, {required String referer});

  Stream<DownloadProgress> download(
    List<MediaItem> items, {
    required String referer,
  });

  void cancelDownload();
}
