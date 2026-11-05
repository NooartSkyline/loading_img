import 'package:flutter/material.dart';
import 'package:loading/core/app_colors.dart';
import 'package:loading/features/media/model/download_progress.dart';

class DownloadDock extends StatelessWidget {
  const DownloadDock({
    super.key,
    required this.selectedCount,
    required this.downloading,
    required this.progress,
    required this.onDownload,
    required this.onCancel,
  });

  final int selectedCount;
  final bool downloading;
  final DownloadProgress? progress;
  final VoidCallback onDownload;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final current = progress;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.line),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (current != null) ...[
                Text(
                  current.label,
                  style: const TextStyle(color: AppColors.text, fontSize: 13, height: 1.35),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: current.fraction,
                    minHeight: 6,
                    backgroundColor: AppColors.line,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (downloading)
                OutlinedButton(
                  key: const ValueKey('download-button'),
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.text,
                    side: const BorderSide(color: AppColors.line),
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('ยกเลิก'),
                )
              else
                FilledButton(
                  key: const ValueKey('download-button'),
                  onPressed: selectedCount == 0 ? null : onDownload,
                  child: Text('โหลดที่เลือก ($selectedCount)'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
