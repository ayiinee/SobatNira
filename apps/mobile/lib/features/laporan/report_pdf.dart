import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../kloter/demo_production.dart';
import 'printable_report.dart';
import 'production_recap_pdf.dart';

Future<Uint8List> buildReportPdf(
  PrintableReport report, {
  PdfPageFormat? format,
}) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/sobatnira/fonts/Inter-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/sobatnira/fonts/Inter-Bold.ttf'),
  );
  if (!report.isProfit) {
    return buildProductionRecapPdf(
      report,
      regular: regular,
      bold: bold,
      format: format,
    );
  }
  const green = PdfColor.fromInt(0xFF174B35);
  const line = PdfColor.fromInt(0xFFD8DEDB);
  const muted = PdfColor.fromInt(0xFF68736E);
  final document = pw.Document(title: report.title, author: 'SobatNira');
  document.addPage(
    pw.MultiPage(
      pageFormat: format ?? PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      header: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 18),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'SobatNira',
              style: pw.TextStyle(
                fontSize: 10,
                color: green,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              report.title,
              style: pw.TextStyle(
                fontSize: 22,
                color: green,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              '${report.factory} · ${report.period}',
              style: const pw.TextStyle(fontSize: 10, color: muted),
            ),
          ],
        ),
      ),
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 10),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: line)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '${report.synthetic ? 'Data sintetis' : 'Data disahkan'} · SobatNira${report.provisional ? ' · Margin sementara pada kloter terbuka' : ''}',
              style: const pw.TextStyle(fontSize: 9, color: muted),
            ),
            pw.Text(
              '${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: muted),
            ),
          ],
        ),
      ),
      build: (context) => [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            color: green,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                report.totalLabel,
                style: const pw.TextStyle(color: PdfColors.white, fontSize: 11),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                report.totalDisplay,
                style: pw.TextStyle(
                  color: const PdfColor.fromInt(0xFFFACA4D),
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 18),
        pw.Text(
          '${report.rows.length} kloter',
          style: const pw.TextStyle(fontSize: 10, color: muted),
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          columnWidths: {
            0: const pw.FlexColumnWidth(3.5),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FlexColumnWidth(2),
            if (!report.isProfit) 3: const pw.FlexColumnWidth(1.5),
          },
          children: [
            pw.TableRow(
              repeat: true,
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: line)),
              ),
              children: [
                for (final (index, title) in [
                  'Kloter / Pemasok',
                  'Tanggal',
                  report.valueLabel,
                  if (!report.isProfit) 'Rendemen',
                ].indexed)
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 4,
                    ),
                    child: pw.Text(
                      title,
                      textAlign: index > 1
                          ? pw.TextAlign.right
                          : pw.TextAlign.left,
                      style: pw.TextStyle(
                        fontSize: 10,
                        color: green,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            for (final row in report.rows)
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: line, width: .5),
                  ),
                ),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 7,
                      horizontal: 4,
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          row.supplier,
                          style: const pw.TextStyle(fontSize: 10, color: green),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          row.code,
                          style: const pw.TextStyle(fontSize: 8, color: muted),
                        ),
                      ],
                    ),
                  ),
                  for (final (index, value) in [
                    formatDate(row.occurredDate, short: true),
                    row.value,
                    if (!report.isProfit) row.secondary,
                  ].indexed)
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        vertical: 7,
                        horizontal: 4,
                      ),
                      child: pw.Text(
                        value,
                        textAlign: index > 0
                            ? pw.TextAlign.right
                            : pw.TextAlign.left,
                        style: const pw.TextStyle(fontSize: 10, color: green),
                      ),
                    ),
                ],
              ),
          ],
        ),
        if (report.rows.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 24),
            child: pw.Text('Tidak ada data pada periode ini.'),
          ),
        pw.SizedBox(height: 12),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              report.totalLabel,
              style: pw.TextStyle(
                fontSize: 11,
                color: green,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              report.totalDisplay,
              style: pw.TextStyle(
                fontSize: 11,
                color: green,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return document.save();
}
