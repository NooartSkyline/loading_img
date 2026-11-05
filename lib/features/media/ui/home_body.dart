import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loading/core/app_colors.dart';
import 'package:loading/features/media/bloc/media_bloc.dart';
import 'package:loading/features/media/bloc/media_event.dart';
import 'package:loading/features/media/bloc/media_state.dart';
import 'package:loading/features/media/ui/widgets/download_dock.dart';
import 'package:loading/features/media/ui/widgets/link_composer.dart';
import 'package:loading/features/media/ui/widgets/media_grid.dart';
import 'package:loading/features/media/ui/widgets/status_banner.dart';

class HomeBody extends StatelessWidget {
  const HomeBody({
    super.key,
    required this.urlController,
    required this.onPaste,
    required this.splitPane,
    required this.gridColumns,
    required this.layoutKey,
  });

  final TextEditingController urlController;
  final VoidCallback onPaste;
  final bool splitPane;
  final int gridColumns;
  final Key layoutKey;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<MediaBloc, MediaState>(
          builder: (context, state) {
            final form = _FormColumn(
              urlController: urlController,
              onPaste: onPaste,
              state: state,
              showDock: splitPane,
            );
            return KeyedSubtree(
              key: layoutKey,
              child: splitPane
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 380,
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              border: Border(right: BorderSide(color: AppColors.line)),
                            ),
                            child: form,
                          ),
                        ),
                        Expanded(child: _Gallery(state: state, columns: gridColumns)),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        form,
                        Expanded(child: _Gallery(state: state, columns: gridColumns)),
                        if (state.post != null)
                          DownloadDock(
                            selectedCount: state.selectedCount,
                            downloading: state.phase == MediaPhase.downloading,
                            progress: state.progress,
                            onDownload: () => context.read<MediaBloc>().add(const DownloadRequested()),
                            onCancel: () => context.read<MediaBloc>().add(const DownloadCancelled()),
                          ),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _FormColumn extends StatelessWidget {
  const _FormColumn({
    required this.urlController,
    required this.onPaste,
    required this.state,
    required this.showDock,
  });

  final TextEditingController urlController;
  final VoidCallback onPaste;
  final MediaState state;
  final bool showDock;

  @override
  Widget build(BuildContext context) {
    final error = state.errorMessage;
    final success = state.successMessage;
    return Column(
      mainAxisSize: showDock ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Masthead(),
        LinkComposer(
          controller: urlController,
          busy: state.isBusy,
          resolving: state.phase == MediaPhase.resolving,
          onResolve: () {
            context.read<MediaBloc>().add(ResolveRequested(urlController.text));
          },
          onPaste: onPaste,
        ),
        if (error != null)
          StatusBanner(message: error, tone: BannerTone.error)
        else if (success != null)
          StatusBanner(message: success, tone: BannerTone.success),
        if (showDock && state.post != null) ...[
          _SelectionHeader(state: state),
          const Spacer(),
          DownloadDock(
            selectedCount: state.selectedCount,
            downloading: state.phase == MediaPhase.downloading,
            progress: state.progress,
            onDownload: () => context.read<MediaBloc>().add(const DownloadRequested()),
            onCancel: () => context.read<MediaBloc>().add(const DownloadCancelled()),
          ),
        ] else if (showDock)
          const Spacer(),
        if (!showDock && state.post != null) _SelectionHeader(state: state),
      ],
    );
  }
}

class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'โพสต์สาธารณะ',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          SizedBox(height: 2),
          Text(
            'โหลดสื่อ',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery({required this.state, required this.columns});

  final MediaState state;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final post = state.post;
    if (state.phase == MediaPhase.resolving) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('กำลังดึงสื่อ', style: TextStyle(color: AppColors.muted)),
          ],
        ),
      );
    }
    if (post != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              _summary(state),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: MediaGrid(
              items: post.items,
              selectedIds: state.selectedIds,
              columns: columns,
              enabled: state.phase != MediaPhase.downloading,
              onToggle: (id) => context.read<MediaBloc>().add(SelectionToggled(id)),
              onVariant: (itemId, variantId) {
                context.read<MediaBloc>().add(VariantChosen(itemId: itemId, variantId: variantId));
              },
            ),
          ),
        ],
      );
    }
    return const _EmptyStage();
  }

  String _summary(MediaState state) {
    final post = state.post;
    if (post == null) return '';
    final title = post.title?.trim();
    if (title == null || title.isEmpty) {
      return '${post.platformLabel} · ${post.items.length} ไฟล์';
    }
    return '${post.platformLabel} · $title';
  }
}

class _EmptyStage extends StatelessWidget {
  const _EmptyStage();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Step(number: '1', text: 'วางลิงก์โพสต์สาธารณะ'),
          SizedBox(height: 14),
          _Step(number: '2', text: 'เลือกไฟล์ที่ต้องการ'),
          SizedBox(height: 14),
          _Step(number: '3', text: 'ไฟล์ใหญ่จะแบ่ง part แล้วต่อให้เอง'),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Center(
              child: Text(
                number,
                style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: AppColors.muted, height: 1.35),
          ),
        ),
      ],
    );
  }
}

class _SelectionHeader extends StatelessWidget {
  const _SelectionHeader({required this.state});

  final MediaState state;

  @override
  Widget build(BuildContext context) {
    final post = state.post;
    if (post == null) return const SizedBox.shrink();
    final busy = state.phase == MediaPhase.downloading;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Row(
        children: [
          TextButton(
            onPressed: busy ? null : () => context.read<MediaBloc>().add(const SelectionSet(true)),
            child: const Text('เลือกทั้งหมด'),
          ),
          TextButton(
            onPressed: busy ? null : () => context.read<MediaBloc>().add(const SelectionSet(false)),
            child: const Text('ล้างที่เลือก'),
          ),
        ],
      ),
    );
  }
}
