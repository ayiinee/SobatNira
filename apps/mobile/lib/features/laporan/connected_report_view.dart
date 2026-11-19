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
import 'report_table.dart';
import 'report_paginated_list.dart';

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
  Widget build(BuildContext context) => CheckboxListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: const Text('Tampilkan data contoh'),
    value: reports.synthetic,
    onChanged: (value) => reports.setSynthetic(value ?? false),
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
    builder: (context, _) => Column(
      children: [
        NiraTabs(
          labels: const ['Produksi', 'Margin'],
          selected: _tab,
          onSelected: (value) => setState(() => _tab = value),
          height: 43,
          inset: 20,
        ),
        Expanded(child: _report(context)),
      ],
    ),
  );

  Widget _report(BuildContext context) {
    final reports = widget.reports;
    void filter() => filterConnectedReport(context, reports);
    final produced = [
      for (final lot in reports.lots)
        if (lot['calculation'] case final Json calculation) (lot, calculation),
    ];
    final margin = _tab == 1;
    final grade = !margin && _variant == ProductionVariant.grade;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (margin) ...[
          NiraSummaryCard(
            'Margin Produksi',
            reports.amount('productionMarginRupiah', money: true),
            cane: true,
            compactValue: true,
          ),
          const SizedBox(height: NiraSpace.sm),
          NiraSummaryPair(
            first: NiraSummaryCard(
              'Nilai produksi',
              reports.amount('productionValueRupiah', money: true),
              compactValue: true,
            ),
            second: NiraSummaryCard(
              'Total biaya',
              reports.amount('totalCostRupiah', money: true),
              boxes: true,
              compactValue: true,
            ),
          ),
        ] else
          NiraSummaryPair(
            first: NiraSummaryCard(
              'Gula final',
              reports.amount('finalSugarKg', unit: ' kg'),
            ),
            second: NiraSummaryCard(
              'Tebu diterima',
              reports.amount('caneNetKg', unit: ' kg'),
              boxes: true,
            ),
          ),
        const SizedBox(height: NiraSpace.md),
        if (margin)
          MarginChart(
            rows: [
              for (final (lot, calculation) in produced)
                AnalyticsRow(
                  lot['supplier'] as String,
                  lot['code'] as String,
                  reportMoney(calculation['productionMarginRupiah']),
                  '',
                ),
            ],
            onFilter: filter,
          )
        else
          ProductionChart.report(
            lots: [
              for (final (lot, calculation) in produced)
                _chartLot(lot, calculation),
            ],
            variant: _variant,
            onVariant: (variant) => setState(() => _variant = variant),
            period: (reports.filter, reports.synthetic),
            onFilter: filter,
          ),
        _ReportSourceControl(reports),
        Text(
          '${reports.period} · ${reports.synthetic ? 'Data sintetis' : 'Data disahkan'}',
          style: niraText(NiraType.caption, color: niraLeaf),
        ),
        ConnectedReportStatus(reports: reports),
        const SizedBox(height: NiraSpace.md),
      ],
    );

    if (grade) {
      final total = reports.data == null
          ? 0.0
          : _number(reports.totals['finalSugarKg']);
      return ReportTable<Json>(
        title: 'Komposisi Grade',
        columns: const ['Grade', 'Berat', 'Porsi'],
        rows: reports.grades,
        scrollHeader: header,
        resetToken: ('grade', reports.data),
        leading: (row) =>
            Text('Grade ${row['code']}', style: niraText(NiraType.body)),
        value: (row) => '${reportNumber(row['weightKg'])} kg',
        secondary: (row) => total == 0
            ? '—'
            : '${(_number(row['weightKg']) / total * 100).toStringAsFixed(1).replaceAll('.', ',')}%',
        onTap: (row) => _detail(null, grade: row['code'] as String),
      );
    }
    return ReportTable<Json>(
      title: margin ? 'Detail margin kloter' : 'Rendemen',
      columns: margin
          ? const ['Pemasok', 'Margin']
          : const ['Pemasok', 'Gula final', 'Rendemen'],
      rows: reports.lots,
      scrollHeader: header,
      resetToken: (_tab, reports.data),
      leading: _lotLabel,
      value: (lot) {
        final calculation = lot['calculation'] as Json?;
        if (calculation == null) return '—';
        return margin
            ? reportMoney(calculation['productionMarginRupiah'])
            : '${reportNumber(calculation['finalSugarKg'])} kg';
      },
      secondary: margin
          ? null
          : (lot) {
              final calculation = lot['calculation'] as Json?;
              return calculation == null
                  ? '—'
                  : '${reportNumber(calculation['rendemenPercent'])}%';
            },
      onTap: _detail,
    );
  }
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
    super.key,
  });
  final Json data;
  final Json? lot, batch;
  final String? grade;
  final NiraTab navigationTab;
  final ValueChanged<NiraTab> onNavigate;
  List<Widget> _marginDetails(Json calculation, String label) {
    final costs = calculation['costs'] as Json;
    return [
      const SizedBox(height: NiraSpace.md),
      NiraSummaryCard(
        label,
        reportMoney(calculation['productionMarginRupiah']),
      ),
      const Text('Margin kumulatif batch sah dengan seluruh biaya kloter.'),
      DetailMetrics([
        (
          'Nilai produksi kloter',
          reportMoney(calculation['productionValueRupiah']),
        ),
        ('Total biaya kloter', reportMoney(calculation['totalCostRupiah'])),
        ('Biaya tebu', reportMoney(costs['caneRupiah'])),
        ('Operasional', reportMoney(costs['operationalRupiah'])),
        ('Bahan', reportMoney(costs['ingredientRupiah'])),
        ('Biaya lain', reportMoney(costs['otherRupiah'])),
      ]),
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
            : _marginDetails(calculation, 'Margin kumulatif kloter'),
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
    return NiraScaffold(
      tab: navigationTab,
      onNavigate: onNavigate,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          niraPageInset(context),
          niraPageInset(context),
          niraPageInset(context),
          NiraSpace.lg,
        ),
        children: [
          DetailTitle(
            grade != null ? 'Detail Grade' : 'Produksi dan margin kloter',
            inset: 0,
          ),
          Text(data['synthetic'] == true ? 'Data sintetis' : 'Data disahkan'),
          const SizedBox(height: NiraSpace.md),
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
            for (final source in (data['items'] as List).cast<Json>())
              for (final b in (source['batches'] as List).cast<Json>())
                for (final g in (b['grades'] as List).cast<Json>())
                  if (g['code'] == grade)
                    ListTile(
                      title: Text('${source['code']} · ${b['code']}'),
                      subtitle: Text(
                        '${reportNumber(g['weightKg'])} kg · ${reportMoney(g['pricePerKgRupiah'])}/kg',
                      ),
                      trailing: Text(reportMoney(g['exactValueRupiah'])),
                      onTap: () => Navigator.of(context).push<void>(
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
          ] else ...[
            Text(
              '${lot!['code']} · ${lot!['supplier']}',
              style: niraText(NiraType.title),
            ),
            Text(
              formatDate(
                DateTime.parse(lot!['receivedAt'] as String).toLocal(),
              ),
            ),
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
            if (calculation != null)
              ..._marginDetails(calculation, 'Margin Produksi'),
            const DetailSectionTitle('Batch sah'),
            ReportPaginatedList<Json>(
              items: batches,
              builder: (rows) => Column(
                children: [
                  for (final b in rows)
                    ListTile(
                      title: Text(b['code'] as String),
                      subtitle: Text('${reportNumber(b['finalSugarKg'])} kg'),
                      trailing: Text(reportMoney(b['exactValueRupiah'])),
                      onTap: () => Navigator.of(context).push<void>(
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
            ),
          ],
        ],
      ),
    );
  }
}
