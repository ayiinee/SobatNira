import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/features/kloter/connected_production.dart';
import 'package:sobatnira/features/laporan/connected_reports.dart';
import 'package:sobatnira/features/laporan/connected_report_controls.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';

final scope = FactoryScope.fromJson({
  'tenantId': 'tenant',
  'factoryId': 'factory',
  'factoryName': 'Factory',
  'tenantName': 'Tenant',
  'role': 'owner',
});
http.Response response(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);
Json summary() => {
  'view': 'summary',
  'items': [],
  'grades': [],
  'provisional': true,
  'totals': {
    'lotCount': 101,
    'caneNetKg': '125000',
    'productionMarginRupiah': '-9007199254740993',
  },
};
void main() {
  test(
    'home requests only summary; rejected detail never exposes partial rows or totals',
    () async {
      final requests = <Uri>[];
      final api = ReviewApi(
        'token',
        client: MockClient((r) async {
          requests.add(r.url);
          if (r.url.path.endsWith('/counts')) {
            return response({'total': 101, 'open': 101, 'closed': 0});
          }
          if (r.url.path.endsWith('/lots')) {
            return response({'items': [], 'nextCursor': null});
          }
          if (r.url.queryParameters['view'] == 'summary') {
            return response(summary());
          }
          return response({
            'message': 'Persempit periode atau gunakan ekspor asinkron.',
          }, 400);
        }),
      );
      final live = ConnectedProduction(api, scope);
      addTearDown(live.dispose);
      addTearDown(api.close);
      await live.refresh();
      expect(
        requests
            .lastWhere((u) => u.path.endsWith('/production-report'))
            .queryParameters['view'],
        'summary',
      );
      expect(live.reports.totals['lotCount'], 101);
      expect(live.reports.provisional, true);
      expect(live.reports.lots, isEmpty);
      await live.reports.ensureDetails();
      expect(live.reports.error, isA<ReviewApiError>());
      expect(live.reports.data, isNull);
      expect(live.reports.lots, isEmpty);
    },
  );
  testWidgets(
    'paged report shows global totals on every page and retries failed page',
    (tester) async {
      var fail = true;
      final offsets = <String?>[];
      final api = ReviewApi(
        'token',
        client: MockClient((r) async {
          expect(r.headers['authorization'], 'Bearer token');
          offsets.add(r.url.queryParameters['offset']);
          if (r.url.queryParameters['offset'] == '20' && fail) {
            return response({'message': 'Unavailable'}, 503);
          }
          return response({
            ...summary(),
            'view': 'page',
            'items': [
              {
                'lotId': 'id',
                'code': r.url.queryParameters['offset'] == '0'
                    ? 'FIRST'
                    : 'LAST',
                'supplier': 'Supplier',
                'caneNetKg': '1250',
                'calculation': null,
                'batches': [],
              },
            ],
            'nextOffset': r.url.queryParameters['offset'] == '0' ? 20 : null,
          });
        }),
      );
      final reports = ConnectedReports(api, scope);
      addTearDown(reports.dispose);
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(home: PagedReportDetails(reports: reports)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Total seluruh periode: 101 kloter'), findsOneWidget);
      await tester.tap(find.text('Berikutnya'));
      await tester.pumpAndSettle();
      expect(find.text('Coba lagi halaman laporan'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Coba lagi halaman laporan'));
      await tester.pumpAndSettle();
      expect(find.text('LAST'), findsOneWidget);
      expect(find.text('Total seluruh periode: 101 kloter'), findsOneWidget);
      expect(offsets, ['0', '20', '20']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'async export uses supplied idempotency key and authenticated status path',
    () async {
      final api = ReviewApi(
        'token',
        client: MockClient((r) async {
          expect(r.headers['authorization'], 'Bearer token');
          if (r.method == 'POST') {
            expect(r.headers['idempotency-key'], 'stable-key');
            expect(jsonDecode(r.body)['synthetic'], false);
            return response({'id': 'job', 'status': 'QUEUED'}, 202);
          }
          expect(r.url.path, endsWith('/report-exports/job'));
          return response({'id': 'job', 'status': 'READY'});
        }),
      );
      addTearDown(api.close);
      expect(
        (await api.requestReportExport(scope, {
          'synthetic': false,
        }, 'stable-key'))['status'],
        'QUEUED',
      );
      expect((await api.reportExportStatus(scope, 'job'))['status'], 'READY');
    },
  );
}
