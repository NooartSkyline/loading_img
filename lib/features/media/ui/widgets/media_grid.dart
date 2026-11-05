import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:loading/core/app_colors.dart';
import 'package:loading/features/media/model/media_item.dart';
import 'package:loading/features/media/model/media_kind.dart';

class MediaGrid extends StatelessWidget {
  const MediaGrid({
    super.key,
    required this.items,
    required this.selectedIds,
    required this.columns,
    required this.enabled,
    required this.onToggle,
    required this.onVariant,
  });

  final List<MediaItem> items;
  final List<String> selectedIds;
  final int columns;
  final bool enabled;
  final ValueChanged<String> onToggle;
  final void Function(String itemId, String variantId) onVariant;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      key: ValueKey('media-grid-$columns'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: columns >= 3 ? 0.78 : 0.7,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _MediaCard(
          item: item,
          index: index,
          selected: selectedIds.contains(item.id),
          enabled: enabled,
          onToggle: () => onToggle(item.id),
          onVariant: (variantId) => onVariant(item.id, variantId),
        );
      },
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.item,
    required this.index,
    required this.selected,
    required this.enabled,
    required this.onToggle,
    required this.onVariant,
  });

  final MediaItem item;
  final int index;
  final bool selected;
  final bool enabled;
  final VoidCallback onToggle;
  final ValueChanged<String> onVariant;

  @override
  Widget build(BuildContext context) {
    final thumb = item.thumbnailUrl;
    final caption = '${item.kind.label} ${index + 1}';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? AppColors.accent : AppColors.line,
          width: selected ? 1.8 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: enabled ? onToggle : null,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(17),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      child: thumb == null
                          ? const ColoredBox(
                              color: AppColors.surface,
                              child: Icon(
                                Icons.movie_outlined,
                                color: AppColors.muted,
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: thumb,
                              fit: BoxFit.cover,
                              placeholder: (context, url) =>
                                  const ColoredBox(color: AppColors.surface),
                              errorWidget: (context, url, error) =>
                                  const ColoredBox(
                                    color: AppColors.surface,
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: AppColors.muted,
                                    ),
                                  ),
                            ),
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.accent
                              : const Color(0xCC14110E),
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            selected ? Icons.check : Icons.add,
                            color: selected ? AppColors.ink : AppColors.text,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xCC14110E),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          child: Text(
                            caption,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (item.variants.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: PopupMenuButton<String>(
                enabled: enabled,
                initialValue: item.selectedVariantId,
                onSelected: onVariant,
                itemBuilder: (context) => [
                  for (final variant in item.variants)
                    PopupMenuItem<String>(
                      value: variant.id,
                      child: Text(variant.caption),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.selectedVariant.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.expand_more,
                        size: 18,
                        color: AppColors.accent,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Text(
                item.selectedVariant.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
