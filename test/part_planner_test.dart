import 'package:flutter_test/flutter_test.dart';
import 'package:loading/core/app_exception.dart';
import 'package:loading/features/media/data/part_planner.dart';

void main() {
  test('splits a file into contiguous parts', () {
    final parts = planParts(totalBytes: 20, partSize: 8);
    expect(parts, const [
      ByteRange(0, 7),
      ByteRange(8, 15),
      ByteRange(16, 19),
    ]);
    final covered = parts.fold<int>(0, (sum, part) => sum + part.length);
    expect(covered, 20);
    expect(parts.map((part) => part.header).toList(), [
      'bytes=0-7',
      'bytes=8-15',
      'bytes=16-19',
    ]);
  });

  test('keeps a small file as one part', () {
    expect(planParts(totalBytes: 8, partSize: 8), const [ByteRange(0, 7)]);
  });

  test('rejects an empty file', () {
    expect(
      () => planParts(totalBytes: 0, partSize: 8),
      throwsA(isA<AppException>()),
    );
  });
}
