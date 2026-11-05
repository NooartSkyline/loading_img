import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loading/app.dart';
import 'package:loading/features/media/model/media_item.dart';
import 'package:loading/features/media/model/media_kind.dart';
import 'package:loading/features/media/model/media_variant.dart';
import 'package:loading/features/media/ui/widgets/media_grid.dart';

void main() {
  testWidgets('phone shows the link form and rejects an empty link', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const LoadingApp());

    expect(find.byKey(const ValueKey('layout-phone')), findsOneWidget);
    expect(find.text('โหลดสื่อ'), findsOneWidget);
    expect(find.text('หน้าเว็บ'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('resolve-button')));
    await tester.pump();
    expect(find.text('ใส่ลิงก์ก่อน'), findsOneWidget);
  });

  testWidgets('tablet uses the wide layout', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const LoadingApp());

    expect(find.byKey(const ValueKey('layout-tablet')), findsOneWidget);
    expect(find.text('ดึงสื่อ'), findsOneWidget);
  });

  testWidgets('a phone card fits its cell', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaGrid(
            items: [
              MediaItem(
                id: 'ig-image-0',
                kind: MediaKind.image,
                variants: const [
                  MediaVariant(id: 'q0', label: 'คุณภาพสูง', url: 'https://cdn.example/a.jpg'),
                  MediaVariant(id: 'q1', label: 'คุณภาพมาตรฐาน', url: 'https://cdn.example/b.jpg'),
                ],
              ),
            ],
            selectedIds: const ['ig-image-0'],
            columns: 2,
            enabled: true,
            onToggle: (_) {},
            onVariant: (_, _) {},
          ),
        ),
      ),
    );

    expect(find.text('รูป 1'), findsOneWidget);
    expect(find.text('คุณภาพสูง'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the browser tab explains how to capture a stream', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const LoadingApp());
    await tester.tap(find.text('หน้าเว็บ'));
    await tester.pump();

    expect(find.byKey(const ValueKey('layout-browser-phone')), findsOneWidget);
    expect(find.text('เปิดหน้าเว็บที่มีตัวเล่น แล้วกดเล่น\nแอปจะจับสตรีมจากหน้านั้น'), findsOneWidget);
  });
}
