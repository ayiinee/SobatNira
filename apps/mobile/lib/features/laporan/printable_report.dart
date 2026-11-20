import '../kloter/demo_production.dart';
import 'demo_analytics.dart';
import '../kloter/kloter_date_filter.dart';
import 'production_recap.dart';

enum PrintableReportKind { profit, production }

// One immutable snapshot feeds both the on-screen report and its PDF.
class PrintableReport {
  PrintableReport({
    required this.kind,
    required this.factory,
    required this.period,
    required List<AnalyticsRow> rows,
    ProductionRecap? recap,
    this.synthetic = true,
    this.totalDisplayOverride,
    this.connected = false,
    this.provisional = false,
  }) : rows = List.unmodifiable(
         {for (final row in rows) (row.id ?? row.code): row}.values,
       ),
       recap = kind == PrintableReportKind.production
           ? recap ?? ProductionRecap.fromRows(rows)
           : null;

  factory PrintableReport.fromAnalytics(
    PrintableReportKind kind,
    DemoAnalytics analytics, {
    required String factory,
    DemoProduction? production,
  }) {
    final range = analytics.dateFilter?.range;
    final rows = analytics.rowsFor(
      kind == PrintableReportKind.profit
          ? ReportTab.margin
          : ReportTab.production,
    );
    return PrintableReport(
      kind: kind,
      factory: factory,
      period: range == null
          ? 'Semua tanggal'
          : '${formatDate(range.start)} - ${formatDate(range.end)}',
      rows: rows,
      recap: kind == PrintableReportKind.production
          ? ProductionRecap.fromRows(
              rows,
              margins: analytics.rowsFor(ReportTab.margin),
              production:
                  production?.kloter
                      .where(
                        (lot) =>
                            (analytics.dateFilter?.contains(lot.date) ??
                                true) &&
                            (analytics.query.trim().isEmpty ||
                                lot.code.toLowerCase().contains(
                                  analytics.query.trim().toLowerCase(),
                                ) ||
                                lot.supplier.toLowerCase().contains(
                                  analytics.query.trim().toLowerCase(),
                                )),
                      )
                      .toList() ??
                  const [],
            )
          : null,
    );
  }

  factory PrintableReport.fromApprovedLots(
    PrintableReportKind kind, {
    required String factory,
    required KloterDateFilter? filter,
    required List<DemoKloter> lots,
  }) => PrintableReport(
    kind: kind,
    factory: factory,
    period: filter == null
        ? 'Semua tanggal'
        : '${formatDate(filter.range.start)} - ${formatDate(filter.range.end)}',
    rows: const [],
    recap: kind == PrintableReportKind.production
        ? ProductionRecap.fromApprovedLots(
            lots.where((lot) => filter?.contains(lot.date) ?? true),
          )
        : null,
    connected: true,
    synthetic: false,
  );

  final bool connected;
  final PrintableReportKind kind;
  final String factory;
  final String period;
  final List<AnalyticsRow> rows;
  final ProductionRecap? recap;
  final bool synthetic;
  final bool provisional;
  final String? totalDisplayOverride;

  bool get isProfit => kind == PrintableReportKind.profit;
  String get title => isProfit ? 'Laporan laba' : 'Rekap produksi';
  String get totalLabel =>
      isProfit ? 'Total margin kloter' : 'Total gula final';
  String get valueLabel => isProfit ? 'Margin' : 'Gula final';
  String get filename =>
      isProfit ? 'sobatnira-laba.pdf' : 'sobatnira-rekap.pdf';
  num get total => rows.fold<num>(
    0,
    (sum, row) =>
        sum +
        num.parse(
          row.value
              .replaceAll(RegExp(r'[^0-9,.-]'), '')
              .replaceAll('.', '')
              .replaceAll(',', '.'),
        ),
  );
  String get totalDisplay {
    if (totalDisplayOverride != null) return totalDisplayOverride!;
    if (connected || (!isProfit && rows.isEmpty && recap!.kloter.isNotEmpty)) {
      return '-';
    }
    final amount = formatRecapNumber(total);
    return isProfit ? 'Rp$amount' : '${amount}Kg';
  }
}
