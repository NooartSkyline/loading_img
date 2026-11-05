import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loading/core/app_colors.dart';
import 'package:loading/features/browser/bloc/browser_cubit.dart';
import 'package:loading/features/media/ui/widgets/status_banner.dart';

class BrowserBody extends StatelessWidget {
  const BrowserBody({
    super.key,
    required this.urlController,
    required this.onPaste,
    required this.onOpen,
    required this.onDownload,
    required this.view,
    required this.splitPane,
    required this.layoutKey,
  });

  final TextEditingController urlController;
  final VoidCallback onPaste;
  final VoidCallback onOpen;
  final VoidCallback onDownload;
  final Widget view;
  final bool splitPane;
  final Key layoutKey;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<BrowserCubit, BrowserState>(
          builder: (context, state) {
            final composer = _AddressBar(
              controller: urlController,
              busy: state.isBusy,
              onPaste: onPaste,
              onOpen: onOpen,
            );
            final banner = _banner(state);
            final stage = _Stage(opened: state.opened, view: view);
            final streams = _StreamList(state: state);
            final dock = _DownloadBar(state: state, onDownload: onDownload);
            return KeyedSubtree(
              key: layoutKey,
              child: splitPane
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 360,
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              border: Border(
                                right: BorderSide(color: AppColors.line),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                composer,
                                banner,
                                Expanded(child: streams),
                                dock,
                              ],
                            ),
                          ),
                        ),
                        Expanded(child: stage),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        composer,
                        banner,
                        Expanded(child: stage),
                        if (state.streams.isNotEmpty)
                          SizedBox(height: 132, child: streams),
                        dock,
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _banner(BrowserState state) {
    final error = state.errorMessage;
    final success = state.successMessage;
    if (error != null) {
      return StatusBanner(message: error, tone: BannerTone.error);
    }
    if (success != null) {
      return StatusBanner(message: success, tone: BannerTone.success);
    }
    return const SizedBox.shrink();
  }
}

class _AddressBar extends StatelessWidget {
  const _AddressBar({
    required this.controller,
    required this.busy,
    required this.onPaste,
    required this.onOpen,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onPaste;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'หน้าเว็บ',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            enableSuggestions: false,
            minLines: 1,
            maxLines: 2,
            style: const TextStyle(color: AppColors.text),
            decoration: InputDecoration(
              hintText: 'วางลิงก์หน้าเว็บที่มีตัวเล่น',
              suffixIcon: IconButton(
                onPressed: onPaste,
                tooltip: 'วางจากคลิปบอร์ด',
                icon: const Icon(Icons.content_paste_outlined),
              ),
            ),
            onSubmitted: busy ? null : (_) => onOpen(),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const ValueKey('browser-open'),
            onPressed: busy ? null : onOpen,
            child: const Text('เปิดหน้า'),
          ),
        ],
      ),
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({required this.opened, required this.view});

  final bool opened;
  final Widget view;

  @override
  Widget build(BuildContext context) {
    if (!opened) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 28),
        child: Center(
          child: Text(
            'เปิดหน้าเว็บที่มีตัวเล่น แล้วกดเล่น\nแอปจะจับสตรีมจากหน้านั้น',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, height: 1.45),
          ),
        ),
      );
    }
    return ColoredBox(color: AppColors.background, child: view);
  }
}

class _StreamList extends StatelessWidget {
  const _StreamList({required this.state});

  final BrowserState state;

  @override
  Widget build(BuildContext context) {
    final streams = state.streams;
    if (streams.isEmpty) {
      return const Center(
        child: Text('ยังไม่พบสตรีม', style: TextStyle(color: AppColors.muted)),
      );
    }
    return ListView.builder(
      key: const ValueKey('stream-list'),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: streams.length,
      itemBuilder: (context, index) {
        final stream = streams[index];
        final selected = stream.id == state.selectedId;
        return ListTile(
          selected: selected,
          enabled: !state.isBusy,
          onTap: () => context.read<BrowserCubit>().select(stream.id),
          title: Text(
            stream.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? AppColors.accent : AppColors.text,
            ),
          ),
          trailing: Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            color: selected ? AppColors.accent : AppColors.muted,
          ),
        );
      },
    );
  }
}

class _DownloadBar extends StatelessWidget {
  const _DownloadBar({required this.state, required this.onDownload});

  final BrowserState state;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final progress = state.progress;
    final downloading = state.isBusy;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (progress != null) ...[
            Text(
              progress.label,
              style: const TextStyle(color: AppColors.text, fontSize: 13),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress.fraction,
                minHeight: 6,
                backgroundColor: AppColors.line,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (downloading)
            OutlinedButton(
              key: const ValueKey('browser-download'),
              onPressed: () => context.read<BrowserCubit>().cancel(),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.text,
                side: const BorderSide(color: AppColors.line),
                minimumSize: const Size(0, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('ยกเลิก'),
            )
          else
            FilledButton(
              key: const ValueKey('browser-download'),
              onPressed: state.selected == null ? null : onDownload,
              child: Text(
                'โหลดสตรีม (${state.selected?.caption ?? 'ยังไม่เลือก'})',
              ),
            ),
        ],
      ),
    );
  }
}
