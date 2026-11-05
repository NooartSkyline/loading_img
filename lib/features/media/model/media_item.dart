import 'package:equatable/equatable.dart';
import 'package:loading/core/app_exception.dart';
import 'package:loading/features/media/model/media_kind.dart';
import 'package:loading/features/media/model/media_variant.dart';

class MediaItem extends Equatable {
  MediaItem({
    required this.id,
    required this.kind,
    required this.variants,
    this.title,
    this.thumbnailUrl,
    String? selectedVariantId,
  }) : selectedVariantId = selectedVariantId ?? _firstId(variants);

  final String id;
  final MediaKind kind;
  final String? title;
  final String? thumbnailUrl;
  final List<MediaVariant> variants;
  final String selectedVariantId;

  static String _firstId(List<MediaVariant> variants) {
    if (variants.isEmpty) {
      throw const AppException('รายการสื่อต้องมีไฟล์อย่างน้อยหนึ่งแบบ');
    }
    return variants.first.id;
  }

  MediaVariant get selectedVariant {
    for (final variant in variants) {
      if (variant.id == selectedVariantId) return variant;
    }
    return variants.first;
  }

  MediaItem withVariant(String variantId) {
    for (final variant in variants) {
      if (variant.id == variantId) {
        return MediaItem(
          id: id,
          kind: kind,
          title: title,
          thumbnailUrl: thumbnailUrl,
          variants: variants,
          selectedVariantId: variantId,
        );
      }
    }
    return this;
  }

  MediaItem withSize(String variantId, int bytes) {
    return MediaItem(
      id: id,
      kind: kind,
      title: title,
      thumbnailUrl: thumbnailUrl,
      variants: [
        for (final variant in variants)
          if (variant.id == variantId) variant.withBytes(bytes) else variant,
      ],
      selectedVariantId: selectedVariantId,
    );
  }

  @override
  List<Object?> get props => [
    id,
    kind,
    title,
    thumbnailUrl,
    variants,
    selectedVariantId,
  ];
}
