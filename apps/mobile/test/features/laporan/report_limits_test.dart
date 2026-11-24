import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/features/kloter/connected_production.dart';
import 'package:sobatnira/features/beranda/home_page.dart';
import 'package:sobatnira/features/beranda/beranda_page.dart';
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
  testWidgets(
    'home keeps global totals after a large report fails and cached report navigation retries once',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var details = 0;
      final api = ReviewApi(
        'token',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/counts')) {
            return response({'total': 101, 'open': 101, 'closed': 0});
          }
          if (request.url.path.endsWith('/lots')) {
            return response({'items': [], 'nextCursor': null});
          }
          if (request.url.queryParameters['view'] == 'summary') {
            return response(summary());
          }
          details++;
          return response({'message': 'Persempit periode laporan.'}, 400);
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: NiraHome(api: api, scope: scope, factories: [scope]),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<BerandaPage>(find.byType(BerandaPage)).summary!.lots,
        '101',
      );
      for (var n = 1; n <= 2; n++) {
        await tester.tap(find.bySemanticsLabel('Laporan'));
        await tester.pumpAndSettle();
        expect(details, n);
        await tester.tap(find.bySemanticsLabel('Beranda'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<BerandaPage>(find.byType(BerandaPage)).summary!.lots,
          '101',
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
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
      expect(live.reports.summary.totals['lotCount'], 101);
      expect(live.reports.summary.provisional, true);
      expect(live.reports.lots, isEmpty);
      await live.reports.ensureDetails();
      expect(live.reports.error, isA<ReviewApiError>());
      expect(live.reports.data, isNull);
      expect(live.reports.lots, isEmpty);
      expect(live.reports.summary.totals['lotCount'], 101);
      expect(live.reports.summary.error, isNull);
      await live.refresh();
      expect(
        requests.where(
          (u) =>
              u.path.endsWith('/production-report') &&
              u.queryParameters['view'] != 'summary',
        ),
        hasLength(1),
      );
      expect(live.reports.summary.totals['lotCount'], 101);
    },
  );
  test(
    'refresh home cancels old detail and identical detail requests coalesce',
    () async {
      final detail = Completer<http.Response>();
      var fullRequests = 0;
      final api = ReviewApi(
        'token',
        client: MockClient((request) async {
          if (request.url.queryParameters['view'] == 'summary') {
            return response(summary());
          }
          fullRequests++;
          return detail.future;
        }),
      );
      final reports = ConnectedReports(api, scope);
      addTearDown(reports.dispose);
      addTearDown(api.close);
      final first = reports.ensureDetails(), second = reports.ensureDetails();
      await Future<void>.delayed(Duration.zero);
      expect(fullRequests, 1);
      await reports.refreshHome();
      detail.complete(
        response({
          ...summary(),
          'view': 'full',
          'totals': {'lotCount': 999},
        }),
      );
      await Future.wait([first, second]);
      expect(reports.data, isNull);
      expect(reports.summary.totals['lotCount'], 101);
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
        (await api.requestReportExport(
          scope,
          from: DateTime.utc(2026, 11, 1),
          before: DateTime.utc(2026, 12, 1),
          synthetic: false,
          requestId: 'stable-key',
        ))['status'],
        'QUEUED',
      );
      expect((await api.reportExportStatus(scope, 'job'))['status'], 'READY');
    },
  );
}
