import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/sobatnira_ui.dart';

void main() {
  testWidgets('badge tinjauan tetap sejajar saat tab aktif', (tester) async {
    for (final width in [360.0, 393.0]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => NiraTabs(
                labels: const ['Semua', 'Perlu Ditinjau', 'Tuntas'],
                selected: selected,
                badgeIndex: 1,
                badgeCount: 3,
                inset: 12,
                onSelected: (value) => setState(() => selected = value),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final label = find.text('Perlu Ditinjau');
      final badge = find.text('3');
      await tester.tap(label);
      for (final duration in [160, 200]) {
        await tester.pump(Duration(milliseconds: duration));
        expect(
          tester.getCenter(label).dy,
          closeTo(tester.getCenter(badge).dy, 1),
        );
        expect(
          tester.getRect(label).right,
          lessThan(tester.getRect(badge).left),
        );
        expect(tester.takeException(), isNull);
      }
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('tab mendukung ukuran intrinsik pada SliverFillRemaining', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    children: [
                      NiraTabs(
                        labels: const ['Tinjau', 'Tuntas'],
                        selected: selected,
                        wideIndicator: true,
                        onSelected: (value) => setState(() => selected = value),
                      ),
                      const Text('Konten Beranda'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Tuntas'));
    await tester.pump(const Duration(milliseconds: 160));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(find.text('Konten Beranda'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
