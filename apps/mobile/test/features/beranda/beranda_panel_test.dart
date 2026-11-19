import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/features/kloter/demo_production.dart';
import 'package:sobatnira/main.dart';
import 'package:sobatnira/features/laporan/demo_analytics.dart';
import 'package:sobatnira/features/kloter/demo_lot_fixture.dart';

void main() {
  testWidgets(
    'panel kloter ditarik tanpa menggeser header dan memuat 7/9 kloter',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 853));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final demo = DemoProduction();
      expect(
        demo.kloter.where((item) => item.status == KloterStatus.review).length,
        7,
      );
      expect(
        demo.kloter.where((item) => item.status == KloterStatus.done).length,
        9,
      );
      demo.dispose();
      await tester.pumpWidget(const SobatNiraApp());
      await tester.pumpAndSettle();
      final analytics = DemoAnalytics();
      addTearDown(analytics.dispose);
      final amount = find.text(demoMoney(analytics.marginTotal));
      final eye = find.byTooltip('Sembunyikan keuntungan');
      expect(
        tester.getCenter(eye).dx,
        greaterThan(tester.getRect(amount).right),
      );
      expect(tester.getCenter(eye).dy, closeTo(tester.getCenter(amount).dy, 1));
      await tester.tap(eye);
      await tester.pumpAndSettle();
      expect(find.text('Rp ••••••'), findsOneWidget);
      await tester.tap(find.byTooltip('Tampilkan keuntungan'));
      await tester.pumpAndSettle();
      expect(amount, findsOneWidget);
      final handle = find.byKey(const ValueKey('beranda-kloter-handle'));
      final header = tester.getTopLeft(find.text('Keuntungan'));
      final originalHandle = tester.getTopLeft(handle);
      await tester.drag(handle, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Keuntungan')), header);
      expect(tester.getTopLeft(handle).dy, lessThan(originalHandle.dy - 40));
      final scrollable = find.descendant(
        of: find.byKey(const ValueKey('beranda-kloter-list')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('MJT-200926-1A'),
        150,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(find.text('MJT-200926-1A').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Tuntas'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('MJT-160926-1A'),
        150,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(find.text('MJT-160926-1A').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tab Laporan dan header Kloter tidak ikut bergulir', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 853));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SobatNiraApp());
    await tester.pumpAndSettle();
    for (final (label, key, tabLabel) in [
      ('Laporan', 'laporan-scroll', 'Produksi'),
      ('Kloter', 'kloter-scroll', 'Semua'),
    ]) {
      await tester.tap(find.bySemanticsLabel(label));
      await tester.pumpAndSettle();
      final search = label == 'Kloter'
          ? tester.getTopLeft(find.byType(TextField))
          : null;
      if (label == 'Laporan') expect(find.byType(TextField), findsNothing);
      final tab = tester.getTopLeft(find.text(tabLabel));
      await tester.drag(find.byKey(PageStorageKey(key)), const Offset(0, -420));
      await tester.pumpAndSettle();
      if (search != null) {
        expect(tester.getTopLeft(find.byType(TextField)), search);
      }
      expect(tester.getTopLeft(find.text(tabLabel)), tab);
      expect(tester.takeException(), isNull);
    }
  });
}
