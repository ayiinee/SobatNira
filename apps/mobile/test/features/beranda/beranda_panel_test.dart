import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/features/kloter/demo_production.dart';
import 'package:sobatnira/main.dart';

void main() {
  testWidgets(
    'panel kloter ditarik tanpa menggeser header dan memuat 7/8 kloter',
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
        8,
      );
      demo.dispose();
      await tester.pumpWidget(const SobatNiraApp());
      await tester.pumpAndSettle();
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
        find.text('MJT-170926-1A'),
        150,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(find.text('MJT-170926-1A').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pencarian dan tab Laporan/Kloter tidak ikut bergulir', (
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
      final search = tester.getTopLeft(find.byType(TextField));
      final tab = tester.getTopLeft(find.text(tabLabel));
      await tester.drag(find.byKey(PageStorageKey(key)), const Offset(0, -420));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(TextField)), search);
      expect(tester.getTopLeft(find.text(tabLabel)), tab);
      expect(tester.takeException(), isNull);
    }
  });
}
