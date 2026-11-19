import 'package:flutter/material.dart';
import '../kloter/kloter_date_filter.dart';
import '../kloter/demo_production.dart';
import '../pekerjaan/review_api.dart';
import 'demo_analytics.dart';
import 'printable_report.dart';
import 'report_export_page.dart';
import 'report_overview.dart';

class ConnectedProfitPage extends StatefulWidget {
  const ConnectedProfitPage({
    required this.api,
    required this.scope,
    super.key,
  });
  final ReviewApi api;
  final FactoryScope scope;
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
    _report = _load();
  }

  @override
  void dispose() {
    _analytics.dispose();
    super.dispose();
  }

  Future<PrintableReport> _load() async {
    final range = _analytics.dateFilter?.range;
    final response = await widget.api.profitReport(
      widget.scope,
      from: range?.start,
      before: range == null
          ? null
          : DateTime(range.end.year, range.end.month, range.end.day + 1),
      synthetic: _synthetic,
    );
    String rupiah(String value) {
      final negative = value.startsWith('-');
      final digits = negative ? value.substring(1) : value;
      return '${negative ? '-' : ''}Rp${digits.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')}';
    }

    return PrintableReport(
      kind: PrintableReportKind.profit,
      factory: widget.scope.factoryName,
      synthetic: _synthetic,
      totalDisplayOverride: rupiah(response['totalMarginRupiah'] as String),
      period: range == null
          ? 'Semua tanggal'
          : '${formatDate(range.start)} - ${formatDate(range.end)}',
      rows: [
        for (final item in response['items'] as List)
          AnalyticsRow(
            item['supplier'] as String,
            item['code'] as String? ?? item['lotId'] as String,
            rupiah(item['calculation']['productionMarginRupiah'] as String),
            '',
            id: item['lotId'] as String,
            date: DateTime.parse(item['receivedAt'] as String).toLocal(),
          ),
      ],
    );
  }

  Future<void> _filter() async {
    final result = await showKloterDateFilter(context, _analytics.dateFilter);
    if (!mounted || result == null) return;
    _analytics.setDateFilter(result.selection);
    setState(() => _report = _load());
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PrintableReport>(
    future: _report,
    builder: (context, snapshot) => ReportExportPage(
      kind: PrintableReportKind.profit,
      analytics: _analytics,
      factory: widget.scope.factoryName,
      report:
          snapshot.data ??
          PrintableReport(
            kind: PrintableReportKind.profit,
            factory: widget.scope.factoryName,
            period: 'Memuat periode',
            rows: const [],
            connected: true,
            synthetic: _synthetic,
            totalDisplayOverride: '—',
          ),
      reportOptions: ReportDataOptions(
        synthetic: _synthetic,
        onChanged: (value) => setState(() {
          _synthetic = value;
          _report = _load();
        }),
      ),
      statusMessage: snapshot.connectionState != ConnectionState.done
          ? const LinearProgressIndicator()
          : snapshot.hasError
          ? TextButton(
              onPressed: () => setState(() => _report = _load()),
              child: const Text('Coba lagi memuat laporan'),
            )
          : null,
      onFilter: _filter,
      onNavigate: (_) => Navigator.of(context).pop(),
    ),
  );
}
