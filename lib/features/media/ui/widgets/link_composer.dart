import 'package:flutter/material.dart';
import 'package:loading/core/app_colors.dart';

class LinkComposer extends StatelessWidget {
  const LinkComposer({
    super.key,
    required this.controller,
    required this.busy,
    required this.resolving,
    required this.onResolve,
    required this.onPaste,
  });

  final TextEditingController controller;
  final bool busy;
  final bool resolving;
  final VoidCallback onResolve;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
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
              const Text(
                'ลิงก์โพสต์',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                minLines: 1,
                maxLines: 3,
                style: const TextStyle(color: AppColors.text, height: 1.35),
                decoration: InputDecoration(
                  hintText: 'วางลิงก์ Instagram, Facebook หรือ VK',
                  filled: true,
                  fillColor: AppColors.background,
                  suffixIcon: IconButton(
                    onPressed: onPaste,
                    tooltip: 'วางจากคลิปบอร์ด',
                    icon: const Icon(Icons.content_paste_outlined),
                  ),
                ),
                onSubmitted: busy ? null : (_) => onResolve(),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('resolve-button'),
                onPressed: busy ? null : onResolve,
                child: resolving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: AppColors.ink,
                        ),
                      )
                    : const Text('ดึงสื่อ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
