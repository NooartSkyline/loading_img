import 'package:flutter/material.dart';
import 'package:loading/core/app_colors.dart';

enum BannerTone { error, success }

class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, required this.message, required this.tone});

  final String message;
  final BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final color = tone == BannerTone.error ? AppColors.danger : AppColors.ok;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                tone == BannerTone.error ? Icons.error_outline : Icons.check_circle_outline,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: color, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
