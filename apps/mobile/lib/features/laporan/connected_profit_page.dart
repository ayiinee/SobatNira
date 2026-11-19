import 'package:flutter/material.dart';

import '../../sobatnira_ui.dart';
import '../kloter/kloter_date_filter.dart';
import '../kloter/demo_production.dart';
import '../pekerjaan/review_api.dart';
import 'demo_analytics.dart';
import 'printable_report.dart';
import 'report_export_page.dart';
import 'production_recap.dart';

class ConnectedProfitPage extends StatefulWidget {
  const ConnectedProfitPage({
    required this.api,
    required this.scope,
    this.kind = PrintableReportKind.profit,
    this.onNavigate,
    this.initialFilter,
    this.initialReport,
    super.key,
  });
  final ReviewApi api;
  final FactoryScope scope;
  final PrintableReportKind kind;
  final ValueChanged<NiraTab>? onNavigate;
  final KloterDateFilter? initialFilter;
  final PrintableReport? initialReport;
  @override
  State<ConnectedProfitPage> createState() => _ConnectedProfitPageState();
}

class _ConnectedProfitPageState extends State<ConnectedProfitPage> {
  final _analytics = DemoAnalytics();
  late Future<PrintableReport> _report;
  bool _synthetic = false;
  @override
  void initState() {
    super.initState();
    _analytics.setDateFilter(widget.initialFilter);
    _report = widget.initialReport == null
        ? _load()
        : Future.value(widget.initialReport!);
  }

  @override
  void dispose() {
    _analytics.dispose();
    super.dispose();
  }

  Future<PrintableReport> _load() => loadFactoryReport(
    widget.api,
    widget.scope,
    widget.kind,
    _analytics.dateFilter,
    synthetic: _synthetic,
  );

  Future<void> _filter() async {
    final result = await showKloterDateFilter(
      context,
      _analytics.dateFilter,
      today: DateTime.now(),
    );
    if (!mounted || result == null) return;
    _analytics.setDateFilter(result.selection);
    setState(() => _report = _load());
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Material(
        child: SafeArea(
          bottom: false,
          child: CheckboxListTile(
            title: const Text('Tampilkan data contoh'),
            value: _synthetic,
            onChanged: (v) => setState(() {
              _synthetic = v ?? false;
              _report = _load();
            }),
          ),
        ),
      ),
      Expanded(
        child: FutureBuilder<PrintableReport>(
          future: _report,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Scaffold(
                appBar: AppBar(
                  title: Text(
                    widget.kind == PrintableReportKind.profit
                        ? 'Laporan laba'
                        : 'Rekap produksi',
                  ),
                ),
                body: Center(
                  child: FilledButton(
                    onPressed: () => setState(() => _report = _load()),
                    child: const Text('Coba lagi memuat laporan'),
                  ),
                ),
              );
            }
            return ReportExportPage(
              kind: widget.kind,
              analytics: _analytics,
              factory: widget.scope.factoryName,
              report: snapshot.data!,
              onFilter: _filter,
              onNavigate:
                  widget.onNavigate ?? (_) => Navigator.of(context).pop(),
            );
          },
        ),
      ),
    ],
  );
}

Future<PrintableReport> loadFactoryReport(
  ReviewApi api,
  FactoryScope scope,
  PrintableReportKind kind,
  KloterDateFilter? filter, {
  bool synthetic = false,
}) async {
  final range = filter?.range;
  final production = kind == PrintableReportKind.production;
  final response = await api.profitReport(
    scope,
    from: range?.start,
    before: range == null
        ? null
        : DateTime(range.end.year, range.end.month, range.end.day + 1),
    synthetic: synthetic,
    recap: production,
  );
  final items = (response['items'] as List).cast<Json>();
  String code(Json item) => item['code'] as String? ?? item['lotId'] as String;
  DateTime date(Json item) =>
      DateTime.parse(item['receivedAt'] as String).toLocal();
  final margin = items.isEmpty
      ? '-'
      : _rupiah(response['totalMarginRupiah'] as String);
  return PrintableReport(
    kind: kind,
    factory: scope.factoryName,
    connected: true,
    synthetic: synthetic,
    provisional: items.any((item) => item['closed'] == false),
    totalDisplayOverride: production
        ? (items.isEmpty
              ? '-'
              : _quantity(response['totalSugarKg'] as String, 'kg'))
        : margin,
    period: range == null
        ? 'Semua tanggal'
        : '${formatDate(range.start)} - ${formatDate(range.end)}',
    rows: [
      for (final item in items)
        AnalyticsRow(
          item['supplier'] as String,
          code(item),
          production
              ? _quantity(item['calculation']['finalSugarKg'] as String, 'kg')
              : _rupiah(
                  item['calculation']['productionMarginRupiah'] as String,
                ),
          production ? '${item['calculation']['rendemenPercent']}%' : '',
          id: item['lotId'] as String,
          date: date(item),
        ),
    ],
    recap: production
        ? ProductionRecap([
            for (final item in items)
              RecapKloter(
                id: item['lotId'] as String,
                code: code(item),
                supplier: item['supplier'] as String,
                date: date(item),
                sugar: _quantity(
                  item['calculation']['finalSugarKg'] as String,
                  'kg',
                ),
                rendemen: '${item['calculation']['rendemenPercent']}%',
                cane: _quantity(
                  item['calculation']['caneNetKg'] as String,
                  'kg',
                ),
                caneType: null,
                vehicle: null,
                margin: _rupiah(
                  item['calculation']['productionMarginRupiah'] as String,
                ),
                batches: (item['batches'] as List? ?? const [])
                    .cast<Json>()
                    .indexed
                    .map((entry) => _batch(entry.$1 + 1, entry.$2)),
              ),
          ], officialMargin: margin)
        : null,
  );
}

RecapBatch _batch(int number, Json batch) => RecapBatch(
  number: number,
  code: batch['code'] as String,
  wokNumber: batch['wokNumber'] as int,
  shift: null,
  brix: null,
  lime: null,
  time: null,
  juice: _quantity(batch['volumeMl'] as String, 'mL'),
  physical: _quantity(batch['physicalWeightKg'] as String, 'kg'),
  grade: (batch['grades'] as List? ?? const [])
      .cast<Json>()
      .map(
        (grade) =>
            '${grade['code']} · ${_quantity(grade['weightKg'] as String, 'kg')}',
      )
      .join(', '),
  verified: true,
);

String _number(String value) {
  final parts = value.split('.');
  final digits = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]}.',
  );
  final fraction = parts.length == 1
      ? ''
      : parts[1].replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? digits : '$digits,$fraction';
}

String _rupiah(String value) => value.startsWith('-')
    ? '-Rp${_number(value.substring(1))}'
    : 'Rp${_number(value)}';
String _quantity(String value, String unit) => '${_number(value)} $unit';
