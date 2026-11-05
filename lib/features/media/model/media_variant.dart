import 'package:equatable/equatable.dart';
import 'package:loading/core/format_bytes.dart';

class MediaVariant extends Equatable {
  const MediaVariant({
    required this.id,
    required this.label,
    required this.url,
    this.bytes,
  });

  final String id;
  final String label;
  final String url;
  final int? bytes;

  String get caption {
    final size = bytes;
    if (size == null || size <= 0 || label.contains('·')) return label;
    return '$label · ${formatBytes(size)}';
  }

  MediaVariant withBytes(int bytes) {
    return MediaVariant(id: id, label: label, url: url, bytes: bytes);
  }

  @override
  List<Object?> get props => [id, label, url, bytes];
}
