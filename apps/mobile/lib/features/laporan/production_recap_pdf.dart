import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../kloter/demo_production.dart';
import 'printable_report.dart';
import 'production_recap.dart';

Future<Uint8List> buildProductionRecapPdf(
  PrintableReport report, {
  required pw.Font regular,
  required pw.Font bold,
  PdfPageFormat? format,
}) async {
  const green = PdfColor.fromInt(0xFF174B35);
  const line = PdfColor.fromInt(0xFFD8DEDB);
  const muted = PdfColor.fromInt(0xFF68736E);
  final recap = report.recap!;
  final document = pw.Document(title: report.title, author: 'SobatNira');
  document.addPage(
    pw.MultiPage(
      pageFormat: format ?? PdfPageFormat.a4.landscape,
      maxPages: 200,
      margin: const pw.EdgeInsets.all(28),
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      header: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 14),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'SobatNira',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: green,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Rekap produksi',
                  style: pw.TextStyle(
                    fontSize: 20,
                    color: green,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  report.factory,
                  style: pw.TextStyle(
                    fontSize: 11,
                    color: green,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  report.period,
                  style: const pw.TextStyle(fontSize: 9, color: muted),
                ),
              ],
            ),
          ],
        ),
      ),
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: line)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '${report.synthetic ? 'Data sintetis' : 'Data disahkan'} · - = belum tercatat · Status mengikuti validasi batch${report.provisional ? ' · Margin sementara pada kloter terbuka' : ''}${report.scopeNote == null ? '' : ' · ${report.scopeNote}'}',
              style: const pw.TextStyle(fontSize: 8, color: muted),
            ),
            pw.Text(
              '${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: muted),
            ),
          ],
        ),
      ),
      build: (context) => [
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            color: green,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Row(
            children: [
              for (final metric in [
                ('Gula final', report.totalDisplay),
                ('Margin tercatat', recap.marginTotal),
                ('Kloter', '${recap.kloter.length}'),
                ('Batch', '${recap.batchCount}'),
              ])
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        metric.$1,
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        metric.$2,
                        style: pw.TextStyle(
                          fontSize: 20,
                          color: const PdfColor.fromInt(0xFFFACA4D),
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        pw.SizedBox(height: 9),
        pw.Text(
          'Gula final tersedia untuk ${recap.sugarCount}/${recap.kloter.length} kloter; margin ${recap.marginCount}/${recap.kloter.length} kloter. Gula final dan rendemen mengikuti catatan kloter; hasil fisik dan grade mengikuti catatan batch.',
          style: const pw.TextStyle(fontSize: 8, color: muted),
        ),
        if (recap.kloter.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 24),
            child: pw.Text('Tidak ada data pada periode ini.'),
          ),
        for (final lot in recap.kloter) ...[
          pw.NewPage(freeSpace: 135),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Text(
                  '${lot.code} · ${lot.supplier}',
                  style: pw.TextStyle(
                    fontSize: 12,
                    color: green,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Text(
                formatDate(lot.date),
                style: const pw.TextStyle(fontSize: 9, color: muted),
              ),
            ],
          ),
          pw.SizedBox(height: 7),
          pw.Wrap(
            spacing: 18,
            runSpacing: 5,
            children: [
              for (final metric in [
                ('Tebu', lot.cane ?? '-'),
                if (lot.juice != null) ('Nira dihasilkan', lot.juice!),
                ('Gula final', lot.sugar),
                ('Rendemen', lot.rendemen),
                ('Margin', lot.margin ?? '-'),
              ])
                pw.Text(
                  '${metric.$1}: ${metric.$2}',
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: green,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            'Jenis tebu: ${lot.caneType ?? '-'} · Kendaraan: ${lot.vehicle ?? '-'}',
            style: const pw.TextStyle(fontSize: 8, color: muted),
          ),
          pw.SizedBox(height: 8),
          if (lot.batches.isEmpty)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(vertical: 12),
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: line)),
              ),
              child: pw.Text(
                'Rincian batch belum tersedia.',
                style: const pw.TextStyle(fontSize: 9, color: muted),
              ),
            )
          else
            pw.Table(
              columnWidths: {
                0: const pw.FlexColumnWidth(1.6),
                for (var i = 1; i < 8; i++) i: const pw.FlexColumnWidth(1),
                8: const pw.FlexColumnWidth(1.3),
              },
              children: [
                pw.TableRow(
                  repeat: true,
                  decoration: const pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFEDF3EE),
                  ),
                  children: [
                    for (final (index, title) in RecapBatch.columns.indexed)
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                          vertical: 7,
                          horizontal: 5,
                        ),
                        child: pw.Text(
                          index == 0 ? '$title / ${lot.code}' : title,
                          style: pw.TextStyle(
                            fontSize: 8,
                            color: green,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                for (final batch in lot.batches)
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(color: line, width: .5),
                      ),
                    ),
                    children: [
                      for (final (index, value) in batch.cells.indexed)
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                            vertical: 7,
                            horizontal: 5,
                          ),
                          child: pw.Text(
                            value,
                            style: pw.TextStyle(
                              fontSize: 9,
                              color: index == 8 && !batch.verified
                                  ? const PdfColor.fromInt(0xFFB97105)
                                  : green,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
        ],
      ],
    ),
  );
  return document.save();
}
