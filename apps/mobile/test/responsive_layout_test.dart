import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/features/kloter/batch_detail_page.dart';
import 'package:sobatnira/features/kloter/demo_production.dart';
import 'package:sobatnira/main.dart';
import 'package:sobatnira/sobatnira_ui.dart';

void main() {
  const devices = [
    ('layar kecil', Size(320, 568), 1.0, FakeViewPadding(top: 24, bottom: 16)),
    ('teks besar', Size(360, 640), 1.8, FakeViewPadding(top: 28, bottom: 24)),
    ('layar lebar', Size(430, 932), 1.0, FakeViewPadding(top: 59, bottom: 34)),
    (
      'landscape',
      Size(740, 360),
      1.3,
      FakeViewPadding(left: 40, right: 20, bottom: 16),
    ),
  ];

  for (final (name, size, textScale, safeArea) in devices) {
    testWidgets('navigasi dan kalender dapat digunakan di $name', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      tester.view.padding = safeArea;
      tester.view.viewPadding = safeArea;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(const SobatNiraApp(connected: false));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      if (size.height < 500 || textScale > 1.5) {
        final homeScroll = find.byKey(
          const PageStorageKey('beranda-compact-scroll'),
        );
        expect(homeScroll, findsOneWidget);
        await tester.drag(homeScroll, const Offset(0, -350));
        await tester.pumpAndSettle();
        final help = find.bySemanticsLabel('Bantuan');
        await tester.ensureVisible(help);
        await tester.pumpAndSettle();
        expect(help.hitTestable(), findsOneWidget);
      }

      final safeRect = Rect.fromLTRB(
        safeArea.left,
        safeArea.top,
        size.width - safeArea.right,
        size.height - safeArea.bottom,
      );
      for (final label in [
        'Laporan',
        'Pengaturan',
        'Kloter',
        'Beranda',
        'Kloter',
      ]) {
        final destination = find.bySemanticsLabel(label);
        expect(destination.hitTestable(), findsOneWidget);
        final bounds = tester.getRect(destination);
        expect(bounds.width, greaterThanOrEqualTo(48));
        expect(bounds.left, greaterThanOrEqualTo(safeRect.left));
        expect(bounds.right, lessThanOrEqualTo(safeRect.right));
        expect(bounds.bottom, lessThanOrEqualTo(safeRect.bottom));
        await tester.tap(destination);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Tab $label');
      }
      if (safeRect.width > niraMaxContentWidth) {
        final contentLeft = safeRect.center.dx - niraMaxContentWidth / 2;
        expect(
          tester.getRect(find.byType(TextField)).left,
          greaterThan(contentLeft),
        );
      }

      await tester.tap(find.byTooltip('Filter tanggal'));
      await tester.pumpAndSettle();
      final range = find.text('Rentang tanggal');
      await tester.ensureVisible(range);
      await tester.tap(range);
      await tester.pumpAndSettle();
      final latestDay = find.text('20');
      await tester.ensureVisible(latestDay);
      expect(latestDay.hitTestable(), findsOneWidget);
      await tester.tap(latestDay);
      await tester.pumpAndSettle();
      final apply = find.text('Terapkan');
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Filter tanggal: Rentang tanggal'), findsOneWidget);
      expect(tester.takeException(), isNull);

      if (size.height < 500) {
        final search = find.byType(TextField);
        await tester.showKeyboard(search);
        tester.view.viewInsets = const FakeViewPadding(bottom: 250);
        tester.view.padding = FakeViewPadding(
          left: safeArea.left,
          right: safeArea.right,
        );
        await tester.enterText(search, 'MJT');
        await tester.pumpAndSettle();
        expect(search.hitTestable(), findsOneWidget);
        expect(find.bySemanticsLabel('Beranda'), findsNothing);
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        tester.view.padding = safeArea;
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Beranda').hitTestable(), findsOneWidget);
      }
    });
  }

  testWidgets('detail batch tetap bisa digulir dan divalidasi di landscape', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(660, 320);
    tester.view.padding = const FakeViewPadding(left: 40, bottom: 20);
    tester.view.viewPadding = tester.view.padding;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final demo = DemoProduction();
    addTearDown(demo.dispose);
    final lot = demo.kloter.firstWhere((lot) => lot.batchesToReview > 0);
    await tester.pumpWidget(
      MaterialApp(
        theme: niraTheme(),
        home: BatchDetailPage(
          batch: lot.batches.last,
          kloterCode: lot.code,
          demo: demo,
          onNavigate: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final gradeTab = find.descendant(
      of: find.byType(NiraTabs),
      matching: find.text('Grade'),
    );
    await tester.scrollUntilVisible(gradeTab, 70);
    await tester.pumpAndSettle();
    await tester.tap(gradeTab);
    await tester.pumpAndSettle();
    final heading = find.text('Hasil dan Grade');
    await tester.scrollUntilVisible(heading, 70);
    await tester.pumpAndSettle();
    expect(heading.hitTestable(), findsOneWidget);
    await tester.tap(find.text('Validasi'));
    await tester.pumpAndSettle();
    expect(find.text('Konfirmasi').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
