import 'package:equatable/equatable.dart';
import 'package:loading/core/format_bytes.dart';

enum DownloadStep { fetching, merging, saving }

class DownloadProgress extends Equatable {
  const DownloadProgress({
    required this.itemIndex,
    required this.itemCount,
    required this.partIndex,
    required this.partCount,
    required this.bytesDone,
    required this.bytesTotal,
    required this.step,
    required this.savedCount,
  });

  final int itemIndex;
  final int itemCount;
  final int partIndex;
  final int partCount;
  final int bytesDone;
  final int bytesTotal;
  final DownloadStep step;
  final int savedCount;

  double? get fraction {
    if (bytesTotal <= 0) return null;
    final value = bytesDone / bytesTotal;
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }

  String get label {
    final file = 'ไฟล์ ${itemIndex + 1}/$itemCount';
    switch (step) {
      case DownloadStep.merging:
        return '$file · กำลังต่อ $partCount part';
      case DownloadStep.saving:
        return '$file · กำลังบันทึกลงคลังภาพ';
      case DownloadStep.fetching:
        final part = partCount > 1 ? ' · part ${partIndex + 1}/$partCount' : '';
        final size = bytesTotal > 0
            ? ' · ${formatBytes(bytesDone)} / ${formatBytes(bytesTotal)}'
            : ' · ${formatBytes(bytesDone)}';
        return '$file$part$size';
    }
  }

  @override
  List<Object?> get props => [
        itemIndex,
        itemCount,
        partIndex,
        partCount,
        bytesDone,
        bytesTotal,
        step,
        savedCount,
      ];
}
