import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/summary_card.dart';
import '../kloter/demo_production.dart';
import '../kloter/kloter_date_filter.dart';
import '../kloter/kloter_detail_widgets.dart';
import 'demo_analytics.dart';
import 'printable_report.dart';
import 'report_pdf.dart';
import 'production_recap_section.dart';

class ReportExportPage extends StatefulWidget {
  const ReportExportPage({
    required this.kind,
    required this.analytics,
    required this.factory,
    required this.onNavigate,
    this.production,
    super.key,
  });

  final PrintableReportKind kind;
  final DemoAnalytics analytics;
  final String factory;
  final ValueChanged<NiraTab> onNavigate;
  final DemoProduction? production;

  @override
  State<ReportExportPage> createState() => _ReportExportPageState();
}

class _ReportExportPageState extends State<ReportExportPage> {
  bool _busy = false;

  Future<void> _filter() async {
    final result = await showKloterDateFilter(
      context,
      widget.analytics.dateFilter,
    );
    if (mounted && result != null) {
      widget.analytics.setDateFilter(result.selection);
    }
  }

  Future<void> _export(PrintableReport report, {bool save = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await buildReportPdf(report);
      if (!mounted) return;
      if (save) {
        await Printing.sharePdf(bytes: bytes, filename: report.filename);
      } else {
        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          name: report.filename,
          dynamicLayout: false,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Laporan belum berhasil dibuka. Coba lagi atau simpan PDF.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.analytics,
      if (widget.production != null) widget.production!,
    ]),
    builder: (context, _) {
      final report = PrintableReport.fromAnalytics(
        widget.kind,
        widget.analytics,
        factory: widget.factory,
        production: widget.production,
      );
      final enabled =
          !_busy && (report.recap?.kloter.isNotEmpty ?? report.rows.isNotEmpty);
      return NiraScaffold(
        tab: NiraTab.beranda,
        onNavigate: widget.onNavigate,
        bottomAction: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            NiraButton(
              _busy ? 'Menyiapkan laporan…' : 'Cetak laporan',
              enabled ? () => _export(report) : null,
            ),
            const SizedBox(height: NiraSpace.xs),
            TextButton.icon(
              onPressed: enabled ? () => _export(report, save: true) : null,
              icon: const Icon(Icons.file_download_outlined, size: 20),
              label: const Text('Simpan PDF'),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DetailTitle(report.title),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  niraInset,
                  NiraSpace.xs,
                  niraInset,
                  NiraSpace.lg,
                ),
                children: [
                  Text(
                    report.factory,
                    style: niraText(NiraType.body, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: NiraSpace.sm),
                  NiraOutline(
                    InkWell(
                      onTap: _busy ? null : _filter,
                      child: Padding(
                        padding: const EdgeInsets.all(NiraSpace.md),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_month,
                              color: niraGreen,
                              size: 22,
                            ),
                            const SizedBox(width: NiraSpace.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Periode laporan',
                                    style: niraText(
                                      NiraType.caption,
                                      color: niraLeaf,
                                    ),
                                  ),
                                  const SizedBox(height: NiraSpace.xs),
                                  Text(
                                    report.period,
                                    style: niraText(
                                      NiraType.body,
                                      weight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: NiraSpace.xs),
                            const Icon(Icons.expand_more, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: NiraSpace.md),
                  NiraSummaryCard(report.totalLabel, report.totalDisplay),
                  if (report.recap case final recap?) ...[
                    const SizedBox(height: NiraSpace.sm),
                    NiraSummaryCard('Margin tercatat', recap.marginTotal),
                    const SizedBox(height: NiraSpace.sm),
                    Text(
                      '${recap.kloter.length} kloter · ${recap.batchCount} batch\nGula final ${recap.sugarCount}/${recap.kloter.length} · Margin ${recap.marginCount}/${recap.kloter.length} kloter',
                      style: niraText(NiraType.caption, color: niraLeaf),
                    ),
                    const SizedBox(height: NiraSpace.lg),
                    ProductionRecapSection(recap: recap),
                  ] else ...[
                    const SizedBox(height: NiraSpace.lg),
                    Text(
                      'Rincian per kloter',
                      style: niraText(
                        NiraType.section,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: NiraSpace.xs),
                    Text(
                      'Data demo · ${report.rows.length} kloter',
                      style: niraText(NiraType.caption, color: niraLeaf),
                    ),
                    const SizedBox(height: NiraSpace.sm),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Pemasok / Kloter',
                            style: niraText(NiraType.caption, color: niraMuted),
                          ),
                        ),
                        Text(
                          report.valueLabel,
                          style: niraText(NiraType.caption, color: niraMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: NiraSpace.sm),
                    const Divider(height: 1, color: niraLine),
                    if (report.rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: NiraSpace.xl,
                        ),
                        child: Text(
                          'Tidak ada data pada periode ini.',
                          style: niraText(NiraType.body, color: niraLeaf),
                        ),
                      ),
                    for (final row in report.rows)
                      _reportRow(row, report.isProfit),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _reportRow(AnalyticsRow row, bool profit) => Container(
    padding: const EdgeInsets.symmetric(vertical: NiraSpace.md),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: niraLine)),
    ),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: NiraSpace.md,
      runSpacing: NiraSpace.sm,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row.supplier,
              style: niraText(NiraType.body, weight: FontWeight.w600),
            ),
            const SizedBox(height: NiraSpace.xs),
            Text(row.code, style: niraText(NiraType.caption, color: niraLeaf)),
            Text(
              formatDate(DateTime(2026, 10, row.day)),
              style: niraText(NiraType.caption, color: niraLeaf),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              row.value,
              style: niraText(NiraType.body, weight: FontWeight.w600),
            ),
            if (!profit) ...[
              const SizedBox(height: NiraSpace.xs),
              Text(
                'Rendemen ${row.secondary}',
                style: niraText(NiraType.caption, color: niraLeaf),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}
