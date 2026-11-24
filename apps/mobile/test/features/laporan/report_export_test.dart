import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:printing/src/method_channel.dart';
import 'package:sobatnira/features/kloter/kloter_date_filter.dart';
import 'package:sobatnira/features/laporan/demo_analytics.dart';
import 'package:sobatnira/features/laporan/printable_report.dart';
import 'package:sobatnira/features/laporan/report_pdf.dart';
import 'package:sobatnira/main.dart';

class _TestPrinting extends MethodChannelPrinting {
  Completer<void> completed = Completer<void>();
  Uint8List? bytes;
  String? filename;
  bool fail = false;
  bool saved = false;

  @override
  Future<bool> sharePdf(
    Uint8List bytes,
    String filename,
    Rect bounds,
    String? subject,
    String? body,
    List<String>? emails,
  ) async {
    this.bytes = bytes;
    this.filename = filename;
    saved = true;
    completed.complete();
    return true;
  }

  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
    bool windowsModernDialog,
  ) async {
    bytes = await onLayout(format);
    filename = name;
    completed.complete();
    if (fail) throw StateError('Printer unavailable');
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'export uses existing rows, shares filtering and keeps an immutable snapshot',
    () {
      final analytics = DemoAnalytics();
      addTearDown(analytics.dispose);
      final profit = PrintableReport.fromAnalytics(
        PrintableReportKind.profit,
        analytics,
        factory: 'Pabrik Uji',
      );
      expect(profit.rows.first, same(analytics.marginRows.first));
      expect(profit.totalDisplay, 'Rp6.290.000');
      final production = PrintableReport.fromAnalytics(
        PrintableReportKind.production,
        analytics,
        factory: 'Pabrik Uji',
      );
      expect(production.totalDisplay, '1.078Kg');
      expect(analytics.tab, ReportTab.production);
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
        PrintableReportKind.profit,
        analytics,
        factory: 'Pabrik Uji',
      );
      expect(filtered.rows.length, 3);
      expect(filtered.totalDisplay, 'Rp1.940.000');
      expect(profit.rows.length, 10);
      expect(() => profit.rows.clear(), throwsUnsupportedError);
      analytics.setDateFilter(KloterDateFilter.preset(KloterPeriod.today));
      final empty = PrintableReport.fromAnalytics(
        PrintableReportKind.profit,
        analytics,
        factory: 'Pabrik Uji',
      );
      expect(empty.rows, isEmpty);
      expect(empty.totalDisplay, 'Rp0');
    },
  );

  test(
    'PDF handles both report types, empty data and a multi-page table',
    () async {
      final analytics = DemoAnalytics();
      addTearDown(analytics.dispose);
      for (final kind in PrintableReportKind.values) {
        final report = PrintableReport.fromAnalytics(
          kind,
          analytics,
          factory: 'Pabrik Uji',
        );
        for (final rows in [
          report.rows,
          <AnalyticsRow>[],
          List.generate(80, (index) {
            final row = report.rows[index % report.rows.length];
            return AnalyticsRow(
              row.supplier,
              'K-$index',
              row.value,
              row.secondary,
              day: row.day,
            );
          }),
        ]) {
          final bytes = await buildReportPdf(
            PrintableReport(
              kind: kind,
              factory: report.factory,
              period: report.period,
              rows: rows,
            ),
          );
          expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
          expect(bytes.length, greaterThan(1000));
        }
      }
    },
  );

  testWidgets(
    'home shortcuts open distinct printable reports and keep their order',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 853));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final original = PrintingPlatform.instance;
      final printing = _TestPrinting();
      PrintingPlatform.instance = printing;
      addTearDown(() => PrintingPlatform.instance = original);
      await tester.pumpWidget(const SobatNiraApp(connected: false));
      await tester.pumpAndSettle();
      final labels = ['Laba', 'Rekap', 'Biaya Ops', 'Bantuan'];
      for (var i = 1; i < labels.length; i++) {
        expect(
          tester.getCenter(find.text(labels[i])).dx,
          greaterThan(tester.getCenter(find.text(labels[i - 1])).dx),
        );
      }
      for (final (label, title, file, row) in [
        ('Laba', 'Laporan laba', 'sobatnira-laba.pdf', 'Sugeng'),
        ('Rekap', 'Rekap produksi', 'sobatnira-rekap.pdf', 'MJT-260926-1A'),
      ]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        expect(find.text(row), findsOneWidget);
        final saveButton = find.ancestor(
          of: find.text('Simpan PDF'),
          matching: find.byWidgetPredicate(
            (widget) => widget is OutlinedButton,
          ),
        );
        expect(saveButton, findsOneWidget);
        final printButton = find.widgetWithText(FilledButton, 'Cetak laporan');
        expect(
          tester.getTopLeft(saveButton).dy -
              tester.getBottomLeft(printButton).dy,
          greaterThanOrEqualTo(8),
        );
        printing.completed = Completer<void>();
        await tester.tap(find.text('Cetak laporan'));
        await tester.runAsync(
          () => printing.completed.future.timeout(const Duration(seconds: 20)),
        );
        await tester.pumpAndSettle();
        expect(printing.filename, file);
        expect(String.fromCharCodes(printing.bytes!.take(5)), '%PDF-');
        printing.completed = Completer<void>();
        printing.saved = false;
        await tester.tap(find.text('Simpan PDF'));
        await tester.runAsync(
          () => printing.completed.future.timeout(const Duration(seconds: 20)),
        );
        await tester.pumpAndSettle();
        expect(printing.saved, isTrue);
        expect(printing.filename, file);
        expect(String.fromCharCodes(printing.bytes!.take(5)), '%PDF-');
        await tester.tap(find.byTooltip('Kembali'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Biaya Ops'));
      await tester.pumpAndSettle();
      expect(find.text('Simpan perubahan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty period disables export and printer errors allow retry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final original = PrintingPlatform.instance;
    final printing = _TestPrinting()..fail = true;
    PrintingPlatform.instance = printing;
    addTearDown(() => PrintingPlatform.instance = original);
    await tester.pumpWidget(const SobatNiraApp(connected: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laba'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cetak laporan'));
    await tester.runAsync(
      () => printing.completed.future.timeout(const Duration(seconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Laporan belum berhasil dibuka. Coba lagi.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Cetak laporan'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Periode laporan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hari ini'));
    await tester.pumpAndSettle();
    expect(find.text('Rp0'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Cetak laporan'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find
                .ancestor(
                  of: find.text('Simpan PDF'),
                  matching: find.byWidgetPredicate(
                    (widget) => widget is OutlinedButton,
                  ),
                )
                .first,
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
