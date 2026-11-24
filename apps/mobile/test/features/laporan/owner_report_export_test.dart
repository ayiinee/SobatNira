import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/features/kloter/kloter_date_filter.dart';
import 'package:sobatnira/features/laporan/connected_reports.dart';
import 'package:sobatnira/features/laporan/owner_report_export_page.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';

const _id = '10000000-0000-4000-8000-000000000008';
const _path = '/tenants/tenant/factories/factory/report-exports';

http.Response _job(String status, {int code = 200}) => http.Response(
  jsonEncode({
    'id': _id,
    'status': status,
    'synthetic': true,
    if (status == 'READY') 'formats': ['pdf', 'xlsx'],
  }),
  code,
);

Future<void> _open(WidgetTester tester, MockClient client) async {
  final reports =
      ConnectedReports(
          ReviewApi(
            'owner-test-token',
            client: client,
            baseUrl: 'http://127.0.0.1',
          ),
          FactoryScope.fromJson({
            'tenantId': 'tenant',
            'tenantName': 'Tenant Uji',
            'factoryId': 'factory',
            'factoryName': 'Pabrik Uji',
            'role': 'owner',
          }),
          synthetic: true,
        )
        ..filter = KloterDateFilter.preset(
          KloterPeriod.today,
          today: DateTime(2026, 11, 16),
        );
  addTearDown(reports.dispose);
  await tester.pumpWidget(
    MaterialApp(home: OwnerReportExportPage(reports: reports)),
  );
}

void main() {
  testWidgets('retries the same export and downloads only ready artifacts', (
    tester,
  ) async {
    final keys = <String?>[];
    MethodCall? saved;
    const fileChannel = MethodChannel('sobatnira/report-file');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(fileChannel, (call) async {
      saved = call;
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(fileChannel, null));
    await _open(
      tester,
      MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer owner-test-token');
        if (request.method == 'POST') {
          expect(request.url.path, _path);
          expect(jsonDecode(request.body), {
            'from': DateTime(2026, 11, 16).toUtc().toIso8601String(),
            'before': DateTime(2026, 11, 17).toUtc().toIso8601String(),
            'synthetic': true,
          });
          keys.add(request.headers['idempotency-key']);
          return keys.length == 1
              ? http.Response('', 503)
              : _job('QUEUED', code: 202);
        }
        if (request.url.path == '$_path/$_id') return _job('READY');
        expect(request.url.path, '$_path/$_id/files/xlsx');
        return http.Response.bytes(
          [80, 75, 3, 4],
          200,
          headers: {'content-type': ReportFileFormat.xlsx.mimeType},
        );
      }),
    );

    await tester.tap(find.text('Buat laporan'));
    await tester.pumpAndSettle();
    expect(
      find.text('Ekspor laporan belum tersedia. Coba lagi nanti.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(keys.first, isNotNull);
    expect(keys.last, keys.first);
    expect(find.text('Dalam antrean'), findsOneWidget);
    expect(find.text('Unduh XLSX'), findsNothing);

    await tester.tap(find.text('Cek status'));
    await tester.pumpAndSettle();
    expect(find.text('Unduh PDF'), findsOneWidget);
    final xlsx = find.text('Unduh XLSX');
    await tester.ensureVisible(xlsx);
    await tester.pumpAndSettle();
    await tester.tap(xlsx);
    await tester.pumpAndSettle();
    expect(saved?.method, 'save');
    expect(saved?.arguments['filename'], 'sobatnira-laporan-$_id.xlsx');
    expect(saved?.arguments['bytes'], [80, 75, 3, 4]);
  });

  testWidgets(
    'checks scoped status for a WhatsApp ID and handles missing jobs',
    (tester) async {
      var gets = 0;
      await _open(
        tester,
        MockClient((request) async {
          gets++;
          expect(request.url.path, '$_path/$_id');
          expect(request.method, 'GET');
          return http.Response('', 404);
        }),
      );
      await tester.tap(find.text('Cek status'));
      await tester.pumpAndSettle();
      expect(find.text('Masukkan ID ekspor yang valid.'), findsOneWidget);
      expect(gets, 0);
      await tester.enterText(find.byType(TextField), ' $_id ');
      await tester.tap(find.text('Cek status'));
      await tester.pumpAndSettle();
      expect(gets, 1);
      expect(find.text('Data tidak tersedia untuk akun ini.'), findsOneWidget);
      expect(find.text('Unduh XLSX'), findsNothing);
    },
  );

  testWidgets('hides old downloads while a new period fails to export', (
    tester,
  ) async {
    final next = Completer<http.Response>();
    final requests = <String>[];
    await _open(
      tester,
      MockClient((request) {
        expect(request.method, 'POST');
        requests.add(request.body);
        return requests.length == 1
            ? Future.value(_job('READY', code: 202))
            : next.future;
      }),
    );

    await tester.tap(find.text('Buat laporan'));
    await tester.pumpAndSettle();
    expect(find.text('Unduh XLSX'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(
        OutlinedButton,
        '16 November 2026 – 16 November 2026',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bulan ini'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buat laporan'));
    await tester.pump();
    expect(requests, hasLength(2));
    expect(requests.last, isNot(requests.first));
    final downloadsWhileWaiting = find.text('Unduh XLSX').evaluate().length;

    next.complete(http.Response('', 503));
    await tester.pumpAndSettle();
    expect(downloadsWhileWaiting, 0);
    expect(find.text('Unduh PDF'), findsNothing);
    expect(find.text('Unduh XLSX'), findsNothing);
    expect(find.text('File siap diunduh'), findsNothing);
    expect(find.text('Coba lagi'), findsOneWidget);
  });

  for (final status in [408, 429]) {
    testWidgets('reuses the request key after HTTP $status', (tester) async {
      final requests = <http.Request>[];
      await _open(
        tester,
        MockClient((request) async {
          expect(request.method, 'POST');
          requests.add(request);
          return requests.length == 1
              ? http.Response('', status)
              : _job('READY', code: 202);
        }),
      );

      await tester.tap(find.text('Buat laporan'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(requests, hasLength(2));
      expect(requests.first.headers['idempotency-key'], isNotNull);
      expect(
        requests.last.headers['idempotency-key'],
        requests.first.headers['idempotency-key'],
      );
      expect(requests.last.body, requests.first.body);
      expect(find.text('Unduh XLSX'), findsOneWidget);
    });
  }
}
