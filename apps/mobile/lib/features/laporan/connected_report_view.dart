import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../../widgets/summary_card.dart';
import '../kloter/demo_production.dart';
import '../kloter/kloter_date_filter.dart';
import '../kloter/kloter_detail_widgets.dart';
import '../pekerjaan/review_api.dart';
import 'connected_reports.dart';
import 'demo_analytics.dart';
import 'printable_report.dart';
import 'report_export_page.dart';
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

class ConnectedReportControls extends StatelessWidget {
  const ConnectedReportControls({required this.reports, super.key});
  final ConnectedReports reports;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      OutlinedButton.icon(
        onPressed: () => filterConnectedReport(context, reports),
        icon: const Icon(Icons.calendar_month),
        label: Text(reports.period),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('Tampilkan data contoh'),
        value: reports.synthetic,
        onChanged: (value) => reports.setSynthetic(value ?? false),
      ),
      const Text(
        'Tanggal penerimaan kloter · penerimaan dan batch sah. Margin kumulatif dapat berubah sampai produksi selesai.',
        style: TextStyle(fontSize: 12),
      ),
    ],
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
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.reports,
    builder: (context, _) {
      final reports = widget.reports;
      return Column(
        children: [
          NiraTabs(
            labels: const ['Produksi', 'Margin'],
            selected: _tab,
            onSelected: (value) => setState(() => _tab = value),
            height: 43,
            inset: 20,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                niraInset,
                niraInset,
                niraInset,
                112,
              ),
              children: [
                ConnectedReportControls(reports: reports),
                const SizedBox(height: NiraSpace.md),
                ConnectedReportStatus(reports: reports),
                if (reports.data != null) ...[
                  if (_tab == 0)
                    NiraSummaryPair(
                      first: NiraSummaryCard(
                        'Gula final',
                        reports.amount('finalSugarKg', unit: ' kg'),
                      ),
                      second: NiraSummaryCard(
                        'Tebu diterima',
                        reports.amount('caneNetKg', unit: ' kg'),
                      ),
                    )
                  else ...[
                    NiraSummaryCard(
                      'Margin Produksi',
                      reports.amount('productionMarginRupiah', money: true),
                    ),
                    const SizedBox(height: NiraSpace.sm),
                    NiraSummaryPair(
                      first: NiraSummaryCard(
                        'Nilai produksi',
                        reports.amount('productionValueRupiah', money: true),
                      ),
                      second: NiraSummaryCard(
                        'Total biaya',
                        reports.amount('totalCostRupiah', money: true),
                      ),
                    ),
                  ],
                  const SizedBox(height: NiraSpace.md),
                  Text(
                    '${reports.totals['lotCount']} kloter diterima · ${reports.totals['producedLotCount']} kloter menghasilkan · ${reports.totals['batchCount']} batch sah',
                  ),
                  if (reports.lots.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Tidak ada data pada periode ini.'),
                    ),
                  ReportPaginatedList<Json>(
                    items: reports.lots,
                    resetToken: reports.data,
                    builder: (lots) => Column(
                      children: [
                        for (final lot in lots)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(lot['code'] as String),
                            subtitle: Text(
                              '${lot['supplier']} · ${formatDate(DateTime.parse(lot['receivedAt'] as String).toLocal())}',
                            ),
                            trailing: Text(
                              lot['calculation'] == null
                                  ? 'Belum ada hasil sah'
                                  : _tab == 0
                                  ? '${reportNumber((lot['calculation'] as Json)['finalSugarKg'])} kg'
                                  : reportMoney(
                                      (lot['calculation']
                                          as Json)['productionMarginRupiah'],
                                    ),
                            ),
                            onTap: () => _detail(lot),
                          ),
                      ],
                    ),
                  ),
                  if (_tab == 0 && reports.grades.isNotEmpty) ...[
                    const DetailSectionTitle('Hasil per grade'),
                    for (final grade in reports.grades)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Grade ${grade['code']}'),
                        subtitle: Text('${reportNumber(grade['weightKg'])} kg'),
                        trailing: Text(reportMoney(grade['exactValueRupiah'])),
                        onTap: () =>
                            _detail(null, grade: grade['code'] as String),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ],
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
    builder: (context, _) => Material(
      color: niraPaper,
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: niraInset),
              child: ConnectedReportControls(reports: widget.reports),
            ),
          ),
          Expanded(
            child: widget.reports.data == null
                ? Scaffold(
                    appBar: AppBar(
                      title: Text(
                        widget.kind == PrintableReportKind.profit
                            ? 'Laporan laba'
                            : 'Rekap produksi',
                      ),
                    ),
                    body: Center(
                      child: ConnectedReportStatus(reports: widget.reports),
                    ),
                  )
                : ReportExportPage(
                    kind: widget.kind,
                    analytics: _analytics,
                    factory: widget.reports.scope.factoryName,
                    report: widget.reports.printable(widget.kind),
                    onFilter: () =>
                        filterConnectedReport(context, widget.reports),
                    onNavigate: widget.onNavigate,
                  ),
          ),
        ],
      ),
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
    super.key,
  });
  final Json data;
  final Json? lot, batch;
  final String? grade;
  final ValueChanged<NiraTab> onNavigate;
  @override
  Widget build(BuildContext context) {
    final calculation = lot?['calculation'] as Json?;
    final batches = (lot?['batches'] as List? ?? const []).cast<Json>();
    final gradeRow = grade == null
        ? null
        : (data['grades'] as List).cast<Json>().firstWhere(
            (g) => g['code'] == grade,
          );
    return NiraScaffold(
      tab: NiraTab.laporan,
      onNavigate: onNavigate,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          niraInset,
          niraInset,
          niraInset,
          112,
        ),
        children: [
          DetailTitle(
            batch != null
                ? 'Detail batch'
                : grade != null
                ? 'Detail Grade'
                : 'Produksi dan margin kloter',
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
            if (batch != null) ...[
              Text('${batch!['code']} · Wajan ${batch!['wokNumber']}'),
              Text(
                'Waktu masak: ${DateTime.parse(batch!['occurredAt'] as String).toLocal()}',
              ),
              NiraSummaryCard(
                'Nilai produksi batch',
                reportMoney(batch!['exactValueRupiah']),
              ),
              const Text('Nilai batch sebelum pembulatan per kloter.'),
              DetailMetrics([
                (
                  'Gula grade sah',
                  '${reportNumber(batch!['finalSugarKg'])} kg',
                ),
                (
                  'Hasil fisik',
                  '${reportNumber(batch!['physicalWeightKg'])} kg',
                ),
                ('Nira dimasak', '${reportNumber(batch!['quantityMl'])} ml'),
              ]),
              for (final g in (batch!['grades'] as List).cast<Json>())
                ListTile(
                  title: Text('Grade ${g['code']}'),
                  subtitle: Text(
                    '${reportNumber(g['weightKg'])} kg · ${reportMoney(g['pricePerKgRupiah'])}/kg',
                  ),
                  trailing: Text(reportMoney(g['exactValueRupiah'])),
                ),
            ] else
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
            if (calculation != null) ...[
              const SizedBox(height: NiraSpace.md),
              NiraSummaryCard(
                batch == null ? 'Margin Produksi' : 'Margin kumulatif kloter',
                reportMoney(calculation['productionMarginRupiah']),
              ),
              const Text(
                'Margin kumulatif batch sah dengan seluruh biaya kloter; bukan laba bersih penjualan.',
              ),
              DetailMetrics([
                (
                  'Nilai produksi kloter',
                  reportMoney(calculation['productionValueRupiah']),
                ),
                (
                  'Total biaya kloter',
                  reportMoney(calculation['totalCostRupiah']),
                ),
                (
                  'Biaya tebu',
                  reportMoney((calculation['costs'] as Json)['caneRupiah']),
                ),
                (
                  'Operasional',
                  reportMoney(
                    (calculation['costs'] as Json)['operationalRupiah'],
                  ),
                ),
                (
                  'Bahan',
                  reportMoney(
                    (calculation['costs'] as Json)['ingredientRupiah'],
                  ),
                ),
                (
                  'Biaya lain',
                  reportMoney((calculation['costs'] as Json)['otherRupiah']),
                ),
              ]),
            ],
            if (batch == null) ...[
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
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
