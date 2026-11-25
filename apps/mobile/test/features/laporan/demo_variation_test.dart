import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/main.dart';
import 'package:sobatnira/widgets/adaptive_value.dart';
import 'package:sobatnira/features/kloter/demo_lot_fixture.dart';
import 'package:sobatnira/features/kloter/demo_production.dart';
import 'package:sobatnira/features/laporan/demo_analytics.dart';

void main() {
  test('demo lots vary while each batch and grade total reconciles', () {
    final production = DemoProduction();
    final analytics = DemoAnalytics();
    addTearDown(production.dispose);
    addTearDown(analytics.dispose);
    expect(
      production.kloter.map((lot) => lot.weight).toSet().length,
      greaterThan(10),
    );
    expect(
      production.kloter.map((lot) => lot.batches.length).toSet().length,
      greaterThanOrEqualTo(5),
    );
    expect(
      analytics.rendemenRows.take(5).map((row) => row.value).toSet().length,
      5,
    );
    expect(
      analytics.rendemenRows.take(5).map((row) => row.secondary).toSet().length,
      greaterThan(3),
    );
    for (final lot in production.kloter) {
      final source = demoLotFor(lot.code);
      expect(
        lot.batches.fold<int>(
          0,
          (sum, batch) => sum + int.parse(batch.gradeWeight),
        ),
        source.sugarKg,
      );
      expect(
        lot.batches.every(
          (batch) => int.parse(batch.review.fields[0].value) <= 115,
        ),
        isTrue,
      );
    }
    expect(
      [
        'A',
        'B',
        'C',
      ].fold<num>(0, (sum, grade) => sum + analytics.gradeWeight(grade)),
      analytics.sugarTotal,
    );
    expect(analytics.valueTotal - analytics.costTotal, analytics.marginTotal);
  });
  testWidgets(
    'report details retain the selected supplier and its actual batch contributions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const SobatNiraApp(connected: false));
      await tester.pumpAndSettle();
      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tap(find.bySemanticsLabel('Laporan'));
      await tap(find.text('Slamet'));
      expect(find.text('MJT-260926-2A'), findsOneWidget);
      expect(find.text('Slamet'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is NiraValue && widget.value == '1.240',
        ),
        findsOneWidget,
      );
      expect(find.text('72Kg'), findsWidgets);
      expect(find.text('Batch 3'), findsOneWidget);
      expect(find.text('Batch 4'), findsNothing);
      await tap(find.byTooltip('Kembali'));
      await tap(find.text('Darto'));
      expect(find.text('MJT-260926-3A'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is NiraValue && widget.value == '1.800',
        ),
        findsOneWidget,
      );
      expect(find.text('126Kg'), findsWidgets);
      expect(find.text('Batch 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
