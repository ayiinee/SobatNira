import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/features/beranda/beranda_page.dart';
import 'package:sobatnira/features/kloter/batch_detail_page.dart';
import 'package:sobatnira/features/kloter/connected_production.dart';
import 'package:sobatnira/features/kloter/demo_production.dart';
import 'package:sobatnira/features/kloter/kloter_detail_page.dart';
import 'package:sobatnira/features/kloter/kloter_process_page.dart';
import 'package:sobatnira/features/laporan/connected_reports.dart';
import 'package:sobatnira/features/laporan/demo_analytics.dart';
import 'package:sobatnira/features/laporan/laporan_page.dart';
import 'package:sobatnira/features/laporan/printable_report.dart';
import 'package:sobatnira/features/laporan/report_detail_page.dart';
import 'package:sobatnira/features/laporan/report_export_page.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';
import 'package:sobatnira/sobatnira_ui.dart';
import '../../support/large_report_fixture.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/sobatnira/fonts/Inter-$weight.ttf'));
    }
    await font.load();
  });
  for (final width in [320.0, 430.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('large API data across pages at $width and text $scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 950));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final api = ReviewApi('fixture');
        final demo = DemoProduction.empty();
        final analytics = DemoAnalytics();
        final reports =
            ConnectedReports(
                api,
                FactoryScope.fromJson({
                  'tenantId': 'fixture',
                  'tenantName': 'Fixture',
                  'factoryId': 'fixture',
                  'factoryName': 'Fixture',
                }),
              )
              ..loading = false
              ..data = largeReportFixture();
        addTearDown(api.close);
        addTearDown(demo.dispose);
        addTearDown(analytics.dispose);
        addTearDown(reports.dispose);
        final report = reports.data!;
        final lotData = (report['items'] as List).first as Json;
        final lot = connectedLot({
          'id': 'lot',
          'displayCode': lotData['code'],
          'supplierName': lotData['supplier'],
          'receivedAt': lotData['receivedAt'],
          'netWeightGrams': '12345678901234',
          'juiceProducedLiters': '1234567.123456',
          'brix': '18.5',
          'status': 'open',
        });
        Future<void> audit(
          String name,
          Widget page, {
          String? tab,
          String? expandText,
        }) async {
          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey(name),
              theme: niraTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: page,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: name);
          if (tab != null) {
            await tester.tap(find.text(tab).first);
            await tester.pumpAndSettle();
          }
          if (expandText != null) {
            await tester.scrollUntilVisible(
              find.text(expandText),
              300,
              scrollable: find
                  .byWidgetPredicate(
                    (widget) =>
                        widget is Scrollable &&
                        widget.axisDirection == AxisDirection.down,
                  )
                  .first,
            );
            await Scrollable.ensureVisible(
              tester.element(find.text(expandText).first),
              alignment: .2,
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text(expandText).first);
            await tester.pumpAndSettle();
            expect(find.byType(Table), findsOneWidget);
          }
          final scroll = find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          );
          for (var i = 0; i < 5 && scroll.evaluate().isNotEmpty; i++) {
            final state = tester.state<ScrollableState>(scroll.first);
            if (state.position.pixels >= state.position.maxScrollExtent) break;
            await tester.drag(scroll.first, const Offset(0, -500));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: name);
          }
          expect(tester.takeException(), isNull, reason: name);
          await tester.pumpWidget(const SizedBox.shrink());
        }

        await audit(
          'home',
          NiraScaffold(
            tab: NiraTab.beranda,
            onNavigate: (_) {},
            body: BerandaPage(
              kloter: [lot],
              onOpenKloter: (_) {},
              profit: reports.amount('productionMarginRupiah', money: true),
              summary: (
                cane: reports.amount('caneNetKg', unit: ' kg'),
                lots: '1234567890123456',
              ),
            ),
          ),
        );
        for (final tab in ReportTab.values) {
          analytics.setTab(tab);
          await audit(
            'report-${tab.name}',
            NiraScaffold(
              tab: NiraTab.laporan,
              onNavigate: (_) {},
              body: LaporanPage(
                analytics: analytics,
                reports: reports,
                onOpenDetail: (_) {},
              ),
            ),
          );
        }
        for (final kind in ReportDetailKind.values) {
          await audit(
            'detail-${kind.name}',
            ReportDetailPage(
              kind: kind,
              report: report,
              officialLot: lotData,
              row: AnalyticsRow('Grade A', '', '', '12,3%'),
              onNavigate: (_) {},
            ),
          );
        }
        for (final kind in PrintableReportKind.values) {
          await audit(
            'export-${kind.name}',
            ReportExportPage(
              kind: kind,
              analytics: analytics,
              reports: reports,
              factory: 'Pabrik sintetis',
              onNavigate: (_) {},
            ),
            expandText: kind == PrintableReportKind.production
                ? 'KLOTER-SINTETIS-PANJANG-001'
                : null,
          );
        }
        await audit(
          'lot',
          KloterDetailPage(
            kloter: lot,
            demo: demo,
            onNavigate: (_) {},
            production: KloterBatchTile(
              title: 'BATCH-SINTETIS-PANJANG-001',
              juice: '1.234.567,123456 L',
              physicalWeight: '1.234.567,125 kg',
              pending: false,
              onTap: () {},
            ),
          ),
        );
        for (final tab in ['Tebu masuk', 'Penggilingan']) {
          await audit(
            'process-$tab',
            KloterProcessPage(
              kloter: lot,
              demo: demo,
              onNavigate: (_) {},
              loadStock: () async => {
                'onHandMl': '1234567890123456',
                'reservedMl': '123456789',
                'availableMl': '1234567766666667',
              },
            ),
            tab: tab,
          );
        }
        for (final tab in ['Ringkasan', 'Masak', 'Grade']) {
          await audit(
            'batch-$tab',
            BatchDetailPage.official(
              officialTitle: 'BATCH-SINTETIS-PANJANG-001',
              officialReviewed: true,
              officialCancelled: false,
              officialNumber: 1,
              kloterCode: lot.code,
              onNavigate: (_) {},
              officialMargin: '-Rp1.234.567.890.123.456',
              officialData: (
                summary: [
                  DemoField('Nira yang dimasak', '83.500,125123456789 L'),
                  DemoField('Hasil timbang', '1.234.567,125 kg'),
                ],
                cooking: [DemoField('Takaran gamping', '1.234.567,123456 kg')],
                grades: [
                  (
                    code: 'A',
                    weight: '1234567,125',
                    price: 'Rp1.234.567.890.123.456',
                  ),
                ],
                totalWeight: '1.234.567,125 kg',
                value: 'Rp900.719.925.474.099.312.345',
                physicalWeight: '1.234.567,125 kg',
                caneWeight: '12.345.678,901234 kg',
              ),
            ),
            tab: tab,
          );
        }
      });
    }
  }
}
