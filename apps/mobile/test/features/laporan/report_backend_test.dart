import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:sobatnira/features/laporan/connected_reports.dart';
import 'package:sobatnira/features/laporan/demo_analytics.dart';
import 'package:sobatnira/features/laporan/laporan_page.dart';
import 'package:sobatnira/features/laporan/printable_report.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';
import 'package:sobatnira/sobatnira_ui.dart';

const _base = String.fromEnvironment('REPORT_TEST_API');

class _LocalHttpOverrides extends HttpOverrides {}

void main() {
  testWidgets(
    'Flutter reads approved production through NestJS and PostgreSQL',
    (tester) async {
      expect(Uri.parse(_base).host, '127.0.0.1');
      final api = ReviewApi(
        'fixture-admin',
        baseUrl: _base,
        client: IOClient(
          HttpOverrides.runWithHttpOverrides(
            HttpClient.new,
            _LocalHttpOverrides(),
          ),
        ),
      );
      addTearDown(api.close);
      final reports = ConnectedReports(
        api,
        FactoryScope.fromJson({
          'tenantId': const String.fromEnvironment('REPORT_TEST_TENANT'),
          'tenantName': 'Fixture',
          'factoryId': const String.fromEnvironment('REPORT_TEST_FACTORY'),
          'factoryName': 'Pabrik fixture',
          'role': 'admin',
        }),
      );
      addTearDown(reports.dispose);
      await tester.runAsync(reports.refresh);
      expect(reports.error, isNull);
      expect(
        reports.amount('productionMarginRupiah', money: true),
        'Rp475.000',
      );
      expect(reports.totals['lotCount'], 1);
      expect(reports.totals['caneNetKg'], '1250');
      expect(reports.totals['finalSugarKg'], '30');
      final recap = reports.printable(PrintableReportKind.production);
      expect(recap.totalDisplay, '30 kg');
      expect(recap.recap!.batchCount, 1);
      expect(recap.recap!.marginTotal, 'Rp475.000');
      expect(
        recap.recap!.kloter.single.batches.single.code,
        'BATCH-FLUTTER-REPORT',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: niraTheme(),
          home: Scaffold(
            body: LaporanPage(
              analytics: DemoAnalytics(),
              reports: reports,
              onOpenDetail: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('30 kg'), findsWidgets);
      expect(find.text('Gula final per hari (Kg)'), findsOneWidget);
      await tester.tap(find.text('Margin').first);
      await tester.pumpAndSettle();
      expect(find.text('Rp475.000'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
    skip: _base.isEmpty,
  );
}
