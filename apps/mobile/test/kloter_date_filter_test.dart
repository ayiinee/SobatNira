import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/features/kloter/kloter_date_filter.dart';

void main() {
  testWidgets('dialog tanggal di tengah, bisa dipilih dan dibatalkan', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    KloterFilterResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showKloterDateFilter(
                  context,
                  KloterDateFilter.preset(KloterPeriod.today),
                );
              },
              child: const Text('Buka filter'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Buka filter'));
    await tester.pumpAndSettle();
    final rect = tester.getRect(
      find.byKey(const ValueKey('kloter-date-dialog')),
    );
    expect(rect.width, 390);
    expect(rect.center.dx, closeTo(215, 1));
    expect(rect.center.dy, closeTo(400, 1));
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.text('Bulan ini'));
    await tester.pumpAndSettle();
    expect(result?.selection?.period, KloterPeriod.month);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Buka filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tutup filter tanggal'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
}
