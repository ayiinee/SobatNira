import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/features/beranda/beranda_page.dart';
import 'package:sobatnira/features/kloter/connected_production.dart';
import 'package:sobatnira/features/kloter/kloter_date_filter.dart';
import 'package:sobatnira/features/laporan/printable_report.dart';
import 'package:sobatnira/features/laporan/connected_report_view.dart';
import 'package:sobatnira/features/laporan/report_pdf.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';
import 'package:sobatnira/main.dart';

import '../../support/demo_login.dart';

Json _factory(String id) => {
  'tenantId': 'tenant',
  'tenantName': 'Tenant',
  'factoryId': id,
  'factoryName': 'Pabrik $id',
  'role': 'admin',
};

Json _lot(String id, {String receivedAt = '2026-11-10T04:00:00Z'}) => {
  'id': id,
  'displayCode': 'OCR-$id',
  'receivedAt': receivedAt,
  'supplierName': 'Pemasok $id',
  'status': 'open',
  'netWeightGrams': '1250010',
  'juiceProducedLiters': '90',
  'intake': {
    'document': {'revisionNumber': 1},
  },
  'milling': {
    'document': {'revisionNumber': 1},
  },
};

http.Response _json(Object result) => http.Response(
  jsonEncode(result),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  testWidgets(
    'login opens the team home and isolates data when switching factory',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final nextFactory = Completer<http.Response>();
      final api = ReviewApi(
        'local-token',
        client: MockClient((request) async {
          if (request.url.path == '/auth/me') {
            return _json({
              'access': [_factory('A'), _factory('B')],
            });
          }
          if (request.url.path.endsWith('/factories/A/lots')) {
            expect(request.url.queryParameters['includeSummary'], 'true');
            return _json({
              'items': [_lot('A')],
              'total': 1,
            });
          }
          if (request.url.path.endsWith('/factories/B/lots')) {
            return nextFactory.future;
          }
          if (request.url.path.endsWith(
            '/factories/B/production/production-report',
          )) {
            expect(request.headers['authorization'], 'Bearer local-token');
            return _json({
              'totals': {
                'lotCount': 1,
                'producedLotCount': 1,
                'batchCount': 1,
                'caneNetKg': '1250',
                'finalSugarKg': '25',
                'productionMarginRupiah': '375000',
              },
              'grades': [],
              'items': [
                {
                  'lotId': 'B',
                  'code': 'OCR-B',
                  'supplier': 'Pemasok B',
                  'receivedAt': '2026-11-10T04:00:00Z',
                  'caneNetKg': '1250',
                  'closed': false,
                  'calculation': {
                    'finalSugarKg': '25',
                    'rendemenPercent': '2',
                    'caneNetKg': '1250',
                    'productionMarginRupiah': '375000',
                  },
                  'batches': [
                    {
                      'id': 'batch-b',
                      'code': 'BATCH-UJI',
                      'wokNumber': 1,
                      'quantityMl': '40000',
                      'occurredAt': '2026-11-10T06:00:00Z',
                      'physicalWeightKg': '26',
                      'grades': [
                        {'code': 'A', 'weightKg': '25'},
                      ],
                    },
                  ],
                },
              ],
            });
          }
          if (request.url.path.endsWith('/review-notifications') ||
              request.url.path.endsWith('/review-tasks')) {
            expect(request.url.queryParameters['factory_id'], 'B');
            return http.Response('{}', 401);
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
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'admin@example.invalid');
      await tester.enterText(fields.at(1), 'sobatnira-demo');
      final submit = find.widgetWithText(FilledButton, 'Masuk');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.byType(BerandaPage), findsOneWidget);
      for (final tab in ['Beranda', 'Kloter', 'Laporan', 'Pengaturan']) {
        expect(find.text(tab), findsOneWidget);
      }
      expect(find.text('OCR-A'), findsOneWidget);
      expect(find.text('Rp15.745.000'), findsNothing);
      await tester.tap(find.byTooltip('Pilih pabrik'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pabrik B'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('OCR-A'), findsNothing);
      nextFactory.complete(
        _json({
          'items': [_lot('B')],
          'total': 1,
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('OCR-B'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Laporan'));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectedReportView), findsOneWidget);
      expect(find.text('25 kg'), findsWidgets);
      await tester.tap(find.text('Margin').first);
      await tester.pumpAndSettle();
      expect(
        find.text('Margin sementara untuk kloter yang masih terbuka.'),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsLabel('Beranda'));
      await tester.pumpAndSettle();
      final recap = find.text('Rekap');
      await tester.ensureVisible(recap);
      await tester.tap(recap);
      await tester.pumpAndSettle();
      expect(find.text('Simpan PDF'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Beranda'));
      await tester.pumpAndSettle();
      final pekerjaan = find.text('Pekerjaan');
      await tester.ensureVisible(pekerjaan);
      await tester.tap(pekerjaan);
      await tester.pumpAndSettle();
      expect(find.text('Sesi berakhir. Masuk kembali.'), findsOneWidget);
      expect(find.byType(BerandaPage), findsNothing);
    },
  );

  test(
    'connected recap and PDF use the same approved factory-period snapshot',
    () async {
      final report = PrintableReport.fromApprovedLots(
        PrintableReportKind.production,
        factory: 'Pabrik uji',
        filter: KloterDateFilter(
          KloterPeriod.custom,
          DateTimeRange(
            start: DateTime(2026, 11, 10),
            end: DateTime(2026, 11, 10),
          ),
        ),
        lots: [
          connectedLot(_lot('A')),
          connectedLot(_lot('B', receivedAt: '2026-11-11T04:00:00Z')),
          connectedLot({
            ..._lot('C'),
            'intake': null,
            'milling': null,
            'netWeightGrams': null,
          }),
        ],
      );
      expect(report.recap!.kloter.map((lot) => lot.code), ['OCR-A']);
      final lot = report.recap!.kloter.single;
      expect(lot.cane, '1.250,01 kg');
      expect(lot.juice, '90 L');
      expect(lot.batches, isEmpty);
      expect(lot.margin, isNull);
      expect(report.totalDisplay, '-');
      expect(
        utf8.decode((await buildReportPdf(report)).take(4).toList()),
        '%PDF',
      );
    },
  );
}
