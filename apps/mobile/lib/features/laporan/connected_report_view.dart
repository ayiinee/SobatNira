import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/summary_card.dart';
import '../kloter/demo_production.dart';
import '../kloter/kloter_date_filter.dart';
import '../kloter/kloter_detail_widgets.dart';
import '../pekerjaan/review_api.dart';
import 'connected_batch_detail.dart';
import 'connected_reports.dart';
import 'demo_analytics.dart';
import 'printable_report.dart';
import 'report_export_page.dart';
import 'margin_chart.dart';
import 'production_chart.dart';
import 'report_overview.dart';
import 'report_detail_page.dart';
import 'report_detail_layout.dart';

Future<void> filterConnectedReport(
  BuildContext context,
  ConnectedReports reports,
) async {
  final result = await showKloterDateFilter(
    context,
    reports.filter,
    today: DateTime.now(),
  );
  if (result != null) await reports.setFilter(result.selection);
}

class _ReportSourceControl extends StatelessWidget {
  const _ReportSourceControl(this.reports);
  final ConnectedReports reports;

  @override
  Widget build(BuildContext context) => ReportDataOptions(
    synthetic: reports.synthetic,
    onChanged: reports.setSynthetic,
  );
}

class ConnectedReportStatus extends StatelessWidget {
  const ConnectedReportStatus({required this.reports, super.key});
  final ConnectedReports reports;
  @override
  Widget build(BuildContext context) {
    if (reports.loading) {
      return const LinearProgressIndicator();
    }
    if (reports.error != null) {
      return Column(
        children: [
          Text(
            reports.error is ReviewApiError
                ? (reports.error as ReviewApiError).message
                : 'Laporan gagal dimuat.',
          ),
          TextButton(
            onPressed: reports.refresh,
            child: const Text('Coba lagi memuat laporan'),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

class ConnectedReportView extends StatefulWidget {
  const ConnectedReportView({
    required this.reports,
    required this.onNavigate,
    super.key,
  });
  final ConnectedReports reports;
  final ValueChanged<NiraTab> onNavigate;
  @override
  State<ConnectedReportView> createState() => _ConnectedReportViewState();
}

class _ConnectedReportViewState extends State<ConnectedReportView> {
  int _tab = 0;
  void _detail(Json? lot, {String? grade}) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => ConnectedReportDetail(
        data: widget.reports.data!,
        lot: lot,
        grade: grade,
        kind: _tab == 1 ? ReportDetailKind.margin : ReportDetailKind.rendemen,
        onNavigate: widget.onNavigate,
      ),
    ),
  );
  ProductionVariant _variant = ProductionVariant.rendemen;

  ProductionChartLot _chartLot(Json lot, Json calculation) {
    final grades = <String, double>{};
    for (final batch in (lot['batches'] as List).cast<Json>()) {
      for (final grade in (batch['grades'] as List).cast<Json>()) {
        final code = grade['code'] as String;
        final weight = _number(grade['weightKg']);
        grades.update(code, (total) => total + weight, ifAbsent: () => weight);
      }
    }
    return (
      date: DateTime.parse(lot['receivedAt'] as String).toLocal(),
      sugarKg: _number(calculation['finalSugarKg']),
      caneKg: _number(lot['caneNetKg']),
      grades: grades,
    );
  }

  double _number(Object? value) => double.parse(value.toString());

  Widget _lotLabel(Json lot) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(lot['supplier'] as String, style: niraText(NiraType.body)),
      Text(
        lot['code'] as String,
        style: niraText(NiraType.caption, color: niraLeaf),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.reports,
    builder: (context, _) {
      final reports = widget.reports;
      final margin = _tab == 1;
      final grade = !margin && _variant == ProductionVariant.grade;
      final produced = [
        for (final lot in reports.lots)
          if (lot['calculation'] case final Json calculation)
            (lot, calculation),
      ];
      void filter() => filterConnectedReport(context, reports);
      final total = !grade || reports.data == null
          ? 0.0
          : _number(reports.totals['finalSugarKg']);
      return ReportOverview<Json>(
        tab: ReportTab.values[_tab],
        onTab: (tab) => setState(() => _tab = tab.index),
        grade: grade,
        sugar: reports.amount('finalSugarKg', unit: ' kg'),
        cane: reports.amount('caneNetKg', unit: ' kg'),
        margin: reports.amount('productionMarginRupiah', money: true),
        productionValue: reports.amount('productionValueRupiah', money: true),
        cost: reports.amount('totalCostRupiah', money: true),
        chart: margin
            ? MarginChart(
                rows: [
                  for (final (lot, calculation) in produced)
                    AnalyticsRow(
                      lot['supplier'] as String,
                      lot['code'] as String,
                      reportMoney(calculation['productionMarginRupiah']),
                      '',
                      id: lot['lotId'] as String,
                      date: DateTime.parse(
                        lot['receivedAt'] as String,
                      ).toLocal(),
                    ),
                ],
                onFilter: filter,
              )
            : ProductionChart.report(
                lots: [
                  for (final (lot, calculation) in produced)
                    _chartLot(lot, calculation),
                ],
                variant: _variant,
                onVariant: (variant) => setState(() => _variant = variant),
                period: (reports.filter, reports.synthetic),
                onFilter: filter,
              ),
        options: _ReportSourceControl(reports),
        status: ConnectedReportStatus(reports: reports),
        rows: grade ? reports.grades : reports.lots,
        resetToken: (_tab, _variant, reports.data),
        leading: grade
            ? (row) =>
                  Text('Grade ${row['code']}', style: niraText(NiraType.body))
            : _lotLabel,
        value: (row) {
          if (grade) return '${reportNumber(row['weightKg'])} kg';
          final calculation = row['calculation'] as Json?;
          if (calculation == null) return '—';
          return margin
              ? reportMoney(calculation['productionMarginRupiah'])
              : '${reportNumber(calculation['finalSugarKg'])} kg';
        },
        secondary: margin
            ? null
            : (row) {
                if (grade) {
                  return total == 0
                      ? '—'
                      : '${(_number(row['weightKg']) / total * 100).toStringAsFixed(1).replaceAll('.', ',')}%';
                }
                final calculation = row['calculation'] as Json?;
                return calculation == null
                    ? '—'
                    : '${reportNumber(calculation['rendemenPercent'])}%';
              },
        onOpen: (row) => _detail(
          grade ? null : row,
          grade: grade ? row['code'] as String : null,
        ),
      );
    },
  );
}

class ConnectedReportExport extends StatefulWidget {
  const ConnectedReportExport({
    required this.reports,
    required this.kind,
    required this.onNavigate,
    super.key,
  });
  final ConnectedReports reports;
  final PrintableReportKind kind;
  final ValueChanged<NiraTab> onNavigate;
  @override
  State<ConnectedReportExport> createState() => _ConnectedReportExportState();
}

class _ConnectedReportExportState extends State<ConnectedReportExport> {
  final _analytics = DemoAnalytics();
  @override
  void dispose() {
    _analytics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.reports,
    builder: (context, _) => ReportExportPage(
      kind: widget.kind,
      analytics: _analytics,
      factory: widget.reports.scope.factoryName,
      report: widget.reports.printable(widget.kind),
      statusMessage: widget.reports.data == null
          ? ConnectedReportStatus(reports: widget.reports)
          : null,
      reportOptions: _ReportSourceControl(widget.reports),
      onFilter: () => filterConnectedReport(context, widget.reports),
      onNavigate: widget.onNavigate,
    ),
  );
}

class ConnectedReportDetail extends StatelessWidget {
  const ConnectedReportDetail({
    required this.data,
    required this.onNavigate,
    this.lot,
    this.grade,
    this.batch,
    this.navigationTab = NiraTab.laporan,
    this.kind = ReportDetailKind.margin,
    super.key,
  });
  final Json data;
  final Json? lot, batch;
  final String? grade;
  final NiraTab navigationTab;
  final ReportDetailKind kind;
  final ValueChanged<NiraTab> onNavigate;
  List<Widget> _marginDetails(Json calculation, String label) {
    final costs = calculation['costs'] as Json;
    return [
      const SizedBox(height: NiraSpace.md),
      const DetailSectionTitle('Rincian perhitungan'),
      const SizedBox(height: NiraSpace.sm),
      ReportMoneyTable(
        rows: [
          ('Nilai produksi', reportMoney(calculation['productionValueRupiah'])),
          ('Total biaya', reportMoney(calculation['totalCostRupiah'])),
          ('Biaya tebu', reportMoney(costs['caneRupiah'])),
          ('Operasional', reportMoney(costs['operationalRupiah'])),
          ('Bahan', reportMoney(costs['ingredientRupiah'])),
          ('Biaya lain', reportMoney(costs['otherRupiah'])),
        ],
        total: (label, reportMoney(calculation['productionMarginRupiah'])),
      ),
      const SizedBox(height: NiraSpace.md),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final calculation = lot?['calculation'] as Json?;
    if (batch case final approved?) {
      return ConnectedBatchDetail(
        batch: approved,
        lotCode: lot!['code'] as String,
        source: data['synthetic'] == true ? 'Data sintetis' : 'Data disahkan',
        marginDetails: calculation == null
            ? const []
            : [
                const SizedBox(height: NiraSpace.sm),
                DetailMetrics([
                  (
                    'Margin kumulatif kloter',
                    reportMoney(calculation['productionMarginRupiah']),
                  ),
                ]),
              ],
        onNavigate: onNavigate,
        navigationTab: navigationTab,
      );
    }
    final batches = (lot?['batches'] as List? ?? const []).cast<Json>();
    final gradeRow = grade == null
        ? null
        : (data['grades'] as List).cast<Json>().firstWhere(
            (g) => g['code'] == grade,
          );
    return ReportDetailLayout(
      title: grade != null
          ? 'Detail Grade'
          : kind == ReportDetailKind.margin
          ? 'Margin kloter'
          : 'Detail Rendemen',
      tab: navigationTab,
      onNavigate: onNavigate,
      children: [
        if (gradeRow != null) ...[
          NiraSummaryCard(
            'Nilai produksi',
            reportMoney(gradeRow['exactValueRupiah']),
          ),
          DetailMetrics([
            ('Grade $grade', '${reportNumber(gradeRow['weightKg'])} kg'),
          ]),
          const Text('Nilai grade sebelum pembulatan per kloter.'),
          const DetailSectionTitle('Kontribusi per kloter'),
          const SizedBox(height: NiraSpace.sm),
          ReportContributionTable(
            columns: const ['Kloter / Batch', 'Berat', 'Nilai'],
            rows: [
              for (final source in (data['items'] as List).cast<Json>())
                for (final b in (source['batches'] as List).cast<Json>())
                  for (final g in (b['grades'] as List).cast<Json>())
                    if (g['code'] == grade)
                      ReportContribution(
                        '${source['code']} · ${b['code']}',
                        '${reportNumber(g['weightKg'])} kg',
                        reportMoney(g['exactValueRupiah']),
                        note: '${reportMoney(g['pricePerKgRupiah'])}/kg',
                        onOpen: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => ConnectedReportDetail(
                              data: data,
                              lot: source,
                              batch: b,
                              onNavigate: onNavigate,
                              navigationTab: navigationTab,
                            ),
                          ),
                        ),
                      ),
            ],
          ),
        ] else ...[
          ReportEntityCard(
            code: lot!['code'] as String,
            supplier: lot!['supplier'] as String,
            date: formatDate(
              DateTime.parse(lot!['receivedAt'] as String).toLocal(),
            ),
          ),
          const SizedBox(height: NiraSpace.md),
          DetailMetrics([
            ('Tebu diterima', '${reportNumber(lot!['caneNetKg'])} kg'),
            (
              'Gula final',
              calculation == null
                  ? 'Belum ada hasil sah'
                  : '${reportNumber(calculation['finalSugarKg'])} kg',
            ),
            (
              'Rendemen',
              calculation == null
                  ? '—'
                  : '${reportNumber(calculation['rendemenPercent'])}%',
            ),
          ]),
          if (calculation != null && kind == ReportDetailKind.margin)
            ..._marginDetails(calculation, 'Margin Produksi'),
          const SizedBox(height: NiraSpace.lg),
          DetailSectionTitle(
            kind == ReportDetailKind.margin
                ? 'Kontribusi Batch'
                : 'Kontribusi hasil per batch',
          ),
          const SizedBox(height: NiraSpace.sm),
          ReportContributionTable(
            columns: const ['Batch', 'Berat', 'Nilai'],
            rows: [
              for (final b in batches)
                ReportContribution(
                  b['code'] as String,
                  '${reportNumber(b['finalSugarKg'])} kg',
                  reportMoney(b['exactValueRupiah']),
                  onOpen: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => ConnectedReportDetail(
                        data: data,
                        lot: lot,
                        batch: b,
                        onNavigate: onNavigate,
                        navigationTab: navigationTab,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
