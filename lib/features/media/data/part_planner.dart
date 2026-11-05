import 'package:equatable/equatable.dart';
import 'package:loading/core/app_exception.dart';

const int kPartSizeBytes = 8 * 1024 * 1024;
const int kSplitThresholdBytes = 8 * 1024 * 1024;
const int kParallelParts = 3;

class ByteRange extends Equatable {
  const ByteRange(this.start, this.endInclusive);

  final int start;
  final int endInclusive;

  int get length => endInclusive - start + 1;

  String get header => 'bytes=$start-$endInclusive';

  @override
  List<Object?> get props => [start, endInclusive];
}

List<ByteRange> planParts({required int totalBytes, required int partSize}) {
  if (totalBytes <= 0) {
    throw const AppException('ไฟล์ไม่มีข้อมูลให้โหลด');
  }
  if (partSize <= 0) {
    throw const AppException('ขนาด part ไม่ถูกต้อง');
  }
  final parts = <ByteRange>[];
  var start = 0;
  while (start < totalBytes) {
    final end = start + partSize - 1;
    final capped = end >= totalBytes ? totalBytes - 1 : end;
    parts.add(ByteRange(start, capped));
    start = capped + 1;
  }
  return parts;
}
