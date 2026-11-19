import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/features/kloter/demo_production.dart';
import 'package:sobatnira/features/kloter/kloter_date_filter.dart';
import 'package:sobatnira/features/laporan/demo_analytics.dart';
import 'package:sobatnira/features/laporan/printable_report.dart';
import 'package:sobatnira/features/laporan/production_recap.dart';
import 'package:sobatnira/features/laporan/report_export_page.dart';
import 'package:sobatnira/sobatnira_ui.dart';

void main() {
  test(
    'recap joins by code, leaves missing data unavailable and freezes batch values',
    () {
      final production = DemoProduction();
      final analytics = DemoAnalytics();
      addTearDown(production.dispose);
      addTearDown(analytics.dispose);
      production.kloter.setAll(0, production.kloter.reversed.toList());
      final report = PrintableReport.fromAnalytics(
        PrintableReportKind.production,
        analytics,
        factory: 'Uji',
        production: production,
      );
      final recap = report.recap!;
      expect(recap.kloter.length, 17);
      expect(recap.sugarCount, 12);
      expect(
        recap.kloter.firstWhere((lot) => lot.code == 'MJT-200926-1A').sugar,
        '-',
      );
      final lot = recap.kloter.first;
      expect(lot.code, 'MJT-260926-1A');
      expect(lot.supplier, 'Sugeng');
      expect(lot.margin, 'Rp570.000');
      expect(lot.sugar, '90Kg');
      expect(lot.rendemen, '6,0%');
      expect(lot.batches.length, 5);
      expect(lot.batches.first.brix, '18,5 °Bx');
      expect(lot.batches.first.juice, '111L');
      expect(lot.batches.first.physical, '20Kg');
      expect(recap.marginCount, 10);
      expect(recap.marginTotal, 'Rp6.290.000');
      final missingMargin = recap.kloter.firstWhere(
        (lot) => lot.code == 'MJT-240926-1A',
      );
      expect(missingMargin.margin, isNull);
      final missingBatch = recap.kloter.firstWhere(
        (lot) => lot.code == 'MJT-230926-2A',
      );
      expect(missingBatch.batches, isEmpty);
      expect(missingBatch.cane, isNull);
      expect(missingBatch.margin, 'Rp350.000');
      final source = production.kloter.firstWhere(
        (item) => item.code == lot.code,
      );
      production.reopenBatch(source.batches.first);
      production.editBatch(
        source.batches.first,
        source.batches.first.review.fields.first,
        '250',
      );
      expect(lot.batches.first.verified, isTrue);
      expect(lot.batches.first.juice, '111L');
      expect(() => lot.batches.clear(), throwsUnsupportedError);
      final refreshed = PrintableReport.fromAnalytics(
        PrintableReportKind.production,
        analytics,
        factory: 'Uji',
        production: production,
      );
      expect(refreshed.recap!.kloter.first.batches.first.juice, '250L');
      expect(refreshed.recap!.kloter.first.batches.first.verified, isFalse);
      analytics.setDateFilter(
        KloterDateFilter(
          KloterPeriod.custom,
          DateTimeRange(
            start: DateTime(2026, 10, 20),
            end: DateTime(2026, 10, 20),
          ),
        ),
      );
      final filtered = PrintableReport.fromAnalytics(
        PrintableReportKind.production,
        analytics,
        factory: 'Uji',
        production: production,
      );
      expect(filtered.recap!.kloter.length, 3);
      expect(filtered.recap!.batchCount, 12);
      expect(filtered.recap!.marginTotal, 'Rp1.940.000');
      expect(filtered.totalDisplay, '288Kg');
      analytics.setDateFilter(
        KloterDateFilter(
          KloterPeriod.custom,
          DateTimeRange(
            start: DateTime(2026, 10, 13),
            end: DateTime(2026, 10, 13),
          ),
        ),
      );
      final notReported = PrintableReport.fromAnalytics(
        PrintableReportKind.production,
        analytics,
        factory: 'Uji',
        production: production,
      );
      expect(notReported.rows, isEmpty);
      expect(notReported.recap!.kloter.single.code, 'MJT-190926-1A');
      expect(notReported.recap!.batchCount, 5);
      expect(notReported.totalDisplay, '-');
      expect(notReported.recap!.marginTotal, '-');
    },
  );

  test('an unavailable margin is not replaced by zero', () {
    final recap = ProductionRecap.fromRows(
      const [AnalyticsRow('Uji', 'K1', '90Kg', '6%')],
      margins: const [AnalyticsRow('Uji', 'K1', '-', '')],
    );
    expect(recap.marginCount, 0);
    expect(recap.marginTotal, '-');
    expect(recap.kloter.single.margin, isNull);
  });

  testWidgets(
    'recap responds to batch edits and preserves expand/collapse state',
    (tester) async {
      final production = DemoProduction();
      final analytics = DemoAnalytics();
      addTearDown(production.dispose);
      addTearDown(analytics.dispose);
      await tester.binding.setSurfaceSize(const Size(393, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: niraTheme(),
          home: ReportExportPage(
            kind: PrintableReportKind.production,
            analytics: analytics,
            production: production,
            factory: 'Uji',
            onNavigate: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = find.text('MJT-260926-1A');
      await tester.ensureVisible(first);
      await tester.pumpAndSettle();
      expect(find.text('Rincian batch'), findsWidgets);
      production.reopenBatch(production.kloter.first.batches.first);
      production.editBatch(
        production.kloter.first.batches.first,
        production.kloter.first.batches.first.review.fields.first,
        '250',
      );
      await tester.pumpAndSettle();
      expect(find.text('250L'), findsOneWidget);
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(find.text('250L'), findsNothing);
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(find.text('250L'), findsOneWidget);
      final second = find.byType(ExpansionTile).at(1);
      await tester.ensureVisible(second);
      await tester.pumpAndSettle();
      await tester.tap(second);
      await tester.pumpAndSettle();
      expect(find.text('250L'), findsNothing);
      expect(find.text('Rincian batch'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
