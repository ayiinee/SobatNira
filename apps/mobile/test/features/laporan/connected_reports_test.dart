import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/features/laporan/connected_reports.dart';
import 'package:sobatnira/features/laporan/demo_analytics.dart';
import 'package:sobatnira/features/laporan/laporan_page.dart';
import 'package:sobatnira/features/laporan/report_detail_page.dart';
import 'package:sobatnira/features/laporan/printable_report.dart';
import 'package:sobatnira/features/laporan/report_pdf.dart';
import 'package:sobatnira/features/kloter/kloter_date_filter.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';
import 'package:sobatnira/sobatnira_ui.dart';
import 'package:sobatnira/main.dart';
import 'package:sobatnira/widgets/adaptive_value.dart';
import '../../support/demo_login.dart';

final scope = FactoryScope.fromJson({
  'tenantId': 'tenant',
  'tenantName': 'Tenant',
  'factoryId': 'factory',
  'factoryName': 'Pabrik uji',
  'role': 'admin',
});
Json fixture() => {
  'synthetic': false,
  'totals': {
    'lotCount': 2,
    'producedLotCount': 1,
    'batchCount': 1,
    'caneNetKg': '2500.01',
    'finalSugarKg': '30.5',
    'productionValueRupiah': '9007199254740993',
    'totalCostRupiah': '9007199254740994',
    'productionMarginRupiah': '-1',
  },
  'grades': [
    {'code': 'A', 'weightKg': '30.5', 'exactValueRupiah': '9007199254740993'},
  ],
  'items': [
    {
      'lotId': 'one',
      'code': 'DUPLICATE',
      'supplier': 'Pemasok satu',
      'receivedAt': '2026-11-19T01:00:00Z',
      'caneNetKg': '1250',
      'caneType': 'BL',
      'juiceLiters': '100',
      'calculation': {
        'finalSugarKg': '30.5',
        'rendemenPercent': '2.44',
        'productionValueRupiah': '9007199254740993',
        'totalCostRupiah': '9007199254740994',
        'productionMarginRupiah': '-1',
        'costs': {
          'caneRupiah': '9007199254740994',
          'operationalRupiah': '0',
          'ingredientRupiah': '0',
          'otherRupiah': '0',
        },
      },
      'batches': [
        {
          'id': 'batch',
          'code': 'BATCH-REAL',
          'wokNumber': 2,
          'occurredAt': '2026-11-19T03:00:00Z',
          'quantityMl': '100000',
          'physicalWeightKg': '32',
          'finalSugarKg': '30.5',
          'exactValueRupiah': '9007199254740993',
          'grades': [
            {
              'code': 'A',
              'weightKg': '30.5',
              'pricePerKgRupiah': '20001',
              'exactValueRupiah': '9007199254740993',
            },
          ],
        },
      ],
    },
    {
      'lotId': 'two',
      'code': 'DUPLICATE',
      'supplier': 'Pemasok dua',
      'receivedAt': '2026-11-19T02:00:00Z',
      'caneNetKg': '1250.01',
      'caneType': null,
      'juiceLiters': null,
      'calculation': null,
      'batches': [],
    },
  ],
};
http.Response response(Json value) => http.Response(jsonEncode(value), 200);

void main() {
  test(
    'one backend snapshot feeds totals, unique recap identities and PDF without floating point money',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final requests = <Uri>[];
      final reports = ConnectedReports(
        ReviewApi(
          'token',
          client: MockClient((r) async {
            requests.add(r.url);
            return response(fixture());
          }),
        ),
        scope,
      );
      addTearDown(reports.dispose);
      await reports.setFilter(
        KloterDateFilter(
          KloterPeriod.custom,
          DateTimeRange(
            start: DateTime(2026, 11, 19),
            end: DateTime(2026, 11, 19),
          ),
        ),
      );
      expect(
        requests.single.path,
        endsWith('/factories/factory/production/production-report'),
      );
      expect(
        DateTime.parse(requests.single.queryParameters['before']!),
        DateTime(2026, 11, 20).toUtc(),
      );
      expect(requests.single.queryParameters['synthetic'], 'false');
      final profit = reports.printable(PrintableReportKind.profit);
      final recap = reports.printable(PrintableReportKind.production);
      expect(
        reports.amount('productionValueRupiah', money: true),
        'Rp9.007.199.254.740.993',
      );
      expect(profit.totalDisplay, '-Rp1');
      expect(recap.totalDisplay, '30,5 kg');
      expect(recap.recap!.kloter.map((lot) => lot.id), ['one', 'two']);
      expect(recap.recap!.marginTotal, '-Rp1');
      expect(recap.recap!.batchCount, 1);
      expect(
        recap.recap!.kloter.first.batches.single.cells.first,
        'BATCH-REAL',
      );
      expect(
        utf8.decode((await buildReportPdf(recap)).take(4).toList()),
        '%PDF',
      );
      await reports.setSynthetic(true);
      expect(requests.last.queryParameters['synthetic'], 'true');
    },
  );

  test(
    'late responses cannot replace a newer period; failures clear stale totals',
    () async {
      final first = Completer<http.Response>();
      var count = 0;
      final reports = ConnectedReports(
        ReviewApi(
          'token',
          client: MockClient((_) async {
            count++;
            if (count == 1) return first.future;
            if (count == 2) return response({...fixture(), 'items': []});
            return http.Response('{}', 503);
          }),
        ),
        scope,
      );
      addTearDown(reports.dispose);
      final old = reports.refresh();
      await reports.setSynthetic(true);
      first.complete(response(fixture()));
      await old;
      expect(reports.lots, isEmpty);
      await reports.refresh();
      expect(reports.data, isNull);
      expect(reports.amount('productionMarginRupiah', money: true), '—');
      expect(reports.error, isNotNull);
    },
  );

  testWidgets(
    'connected production, margin, grade and batch show backend values and no demo amounts',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final reports = ConnectedReports(
        ReviewApi(
          'token',
          client: MockClient((_) async => response(fixture())),
        ),
        scope,
      );
      addTearDown(reports.dispose);
      await reports.refresh();
      final analytics = DemoAnalytics();
      addTearDown(analytics.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: niraTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: LaporanPage(
                analytics: analytics,
                reports: reports,
                onOpenDetail: (kind) {
                  final row = analytics.selectedRow;
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => ReportDetailPage(
                        kind: kind,
                        row: row,
                        onNavigate: (_) {},
                        report: reports.data,
                        officialLot: reports.lots
                            .where((item) => item['lotId'] == row?.id)
                            .firstOrNull,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('30,5 kg'), findsWidgets);
      expect(find.text('Gula final per hari (Kg)'), findsOneWidget);
      await tester.tap(find.text('Margin').first);
      await tester.pumpAndSettle();
      expect(find.text('-Rp1'), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is NiraValue && widget.value == 'Rp9.007.199.254.740.993',
        ),
        findsOneWidget,
      );
      expect(find.text('Margin per kloter (1000)'), findsOneWidget);
      await tester.ensureVisible(find.text('Pemasok satu'));
      await tester.tap(find.text('Pemasok satu'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('BATCH-REAL'), 400);
      await Scrollable.ensureVisible(
        tester.element(find.text('BATCH-REAL')),
        alignment: .4,
      );
      await tester.pumpAndSettle();
      expect(find.text('Kontribusi Batch'), findsOneWidget);
      expect(find.text('Rp670.000'), findsNothing);
      expect(find.text('-Rp1'), findsWidgets);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Produksi').first);
      await tester.pumpAndSettle();
      analytics.setVariant(ProductionVariant.grade);
      await tester.pumpAndSettle();
      final grade = find.text('Grade A').last;
      await Scrollable.ensureVisible(tester.element(grade), alignment: .4);
      await tester.pumpAndSettle();
      await tester.tap(grade);
      await tester.pumpAndSettle();
      expect(find.text('Detail Grade'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is NiraValue && widget.value == 'Rp9.007.199.254.740.993',
        ),
        findsOneWidget,
      );
      expect(find.text('Kontribusi per kloter'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'home shortcuts and report tab share official totals after authenticated login',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 853));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = ReviewApi(
        'token',
        client: MockClient((request) async {
          if (request.url.path == '/auth/me') {
            return response({
              'access': [
                {
                  'tenantId': 'tenant',
                  'tenantName': 'Tenant',
                  'factoryId': 'factory',
                  'factoryName': 'Pabrik uji',
                  'role': 'admin',
                },
              ],
            });
          }
          if (request.url.path.endsWith('/production-report')) {
            return response(fixture());
          }
          if (request.url.path.endsWith('/lots')) {
            return response({'items': [], 'total': 0});
          }
          return http.Response('{}', 404);
        }),
      );
      await tester.pumpWidget(
        SobatNiraApp(
          connected: true,
          configurationErrors: const [],
          signIn: (_, _) async => api,
        ),
      );
      await openDemoLogin(tester);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'admin@example.invalid',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'synthetic-password',
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Masuk'));
      await tester.tap(find.widgetWithText(FilledButton, 'Masuk'));
      await tester.pumpAndSettle();
      expect(find.text('-Rp1'), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is NiraValue && widget.value == '2.500,01 kg',
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Laba'));
      await tester.tap(find.text('Laba'));
      await tester.pumpAndSettle();
      expect(find.text('Total margin kloter'), findsOneWidget);
      expect(find.text('-Rp1'), findsWidgets);
      await tester.tap(find.byTooltip('Kembali'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Rekap'));
      await tester.tap(find.text('Rekap'));
      await tester.pumpAndSettle();
      expect(find.text('Total gula final'), findsOneWidget);
      expect(find.text('30,5 kg'), findsWidgets);
      expect(find.textContaining('1 batch'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
