import 'package:flutter/foundation.dart';

import '../kloter/kloter_date_filter.dart';
import '../kloter/demo_lot_fixture.dart';
import '../kloter/demo_production.dart';
import '../pekerjaan/review_api.dart';
import 'demo_analytics.dart';
import 'printable_report.dart';
import 'production_recap.dart';

// Decimal strings are formatted without converting money to double (Flutter web).
String reportNumber(Object? value) {
  final parts = (value?.toString() ?? '0').split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]}.',
  );
  final fraction = parts.length < 2
      ? ''
      : parts[1].replaceFirst(RegExp(r'0+$'), '');
  return '$whole${fraction.isEmpty ? '' : ',$fraction'}';
}

String reportMoney(Object? value) {
  final text = value?.toString() ?? '0';
  return '${text.startsWith('-') ? '-' : ''}Rp${reportNumber(text.replaceFirst(RegExp(r'^-'), ''))}';
}

class ConnectedReports extends ChangeNotifier {
  ConnectedReports(this.api, this.scope);
  final ReviewApi api;
  final FactoryScope scope;
  KloterDateFilter? filter;
  bool synthetic = false;
  bool loading = true;
  Object? error;
  Json? data;
  int _generation = 0;
  List<Json> get lots => (data?['items'] as List? ?? const []).cast<Json>();
  List<Json> get grades => (data?['grades'] as List? ?? const []).cast<Json>();
  Json get totals => data?['totals'] as Json? ?? const {};
  bool get provisional =>
      lots.any((lot) => lot['calculation'] != null && lot['closed'] == false);
  List<AnalyticsRow> rows(ReportTab tab) => [
    for (final lot in lots) _reportRow(lot, tab),
  ];
  List<AnalyticsRow> get gradeRows => [
    for (final grade in grades)
      AnalyticsRow(
        'Grade ${grade['code']}',
        '',
        '${reportNumber(grade['weightKg'])} kg',
        reportShare(grade['weightKg'], totals['finalSugarKg']),
        id: grade['code'] as String,
      ),
  ];
  String get period => filter == null
      ? 'Semua tanggal'
      : '${formatDate(filter!.range.start)} - ${formatDate(filter!.range.end)}';
  String amount(String key, {bool money = false, String unit = ''}) =>
      data == null
      ? '—'
      : money
      ? reportMoney(totals[key])
      : '${reportNumber(totals[key])}$unit';

  Future<void> refresh() async {
    final generation = ++_generation;
    loading = true;
    error = null;
    data = null;
    notifyListeners();
    try {
      final range = filter?.range;
      final result = await api.productionReport(
        scope,
        synthetic: synthetic,
        from: range?.start,
        before: range == null
            ? null
            : DateTime(range.end.year, range.end.month, range.end.day + 1),
      );
      if (generation != _generation) return;
      // Treat a malformed response as unavailable, never as an empty zero report.
      if (result['items'] is! List ||
          result['grades'] is! List ||
          result['totals'] is! Map) {
        throw const FormatException('Laporan tidak lengkap.');
      }
      data = result;
    } catch (failure) {
      if (generation != _generation) return;
      error = failure;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> setFilter(KloterDateFilter? value) {
    filter = value;
    return refresh();
  }

  Future<void> setSynthetic(bool value) {
    synthetic = value;
    return refresh();
  }

  PrintableReport printable(PrintableReportKind kind) => PrintableReport(
    kind: kind,
    factory: scope.factoryName,
    period: period,
    synthetic: synthetic,
    connected: true,
    provisional: provisional,
    totalDisplayOverride: amount(
      kind == PrintableReportKind.profit
          ? 'productionMarginRupiah'
          : 'finalSugarKg',
      money: kind == PrintableReportKind.profit,
      unit: kind == PrintableReportKind.production ? ' kg' : '',
    ),
    rows: [
      for (final lot in lots)
        if (lot['calculation'] != null)
          _reportRow(
            lot,
            kind == PrintableReportKind.profit
                ? ReportTab.margin
                : ReportTab.production,
          ),
    ],
    recap: kind == PrintableReportKind.profit
        ? null
        : ProductionRecap([
            for (final lot in lots)
              RecapKloter(
                id: lot['lotId'] as String,
                code: lot['code'] as String,
                supplier: lot['supplier'] as String,
                date: DateTime.parse(lot['receivedAt'] as String).toLocal(),
                sugar: lot['calculation'] == null
                    ? '-'
                    : '${reportNumber((lot['calculation'] as Json)['finalSugarKg'])} kg',
                rendemen: lot['calculation'] == null
                    ? '-'
                    : '${reportNumber((lot['calculation'] as Json)['rendemenPercent'])}%',
                cane: '${reportNumber(lot['caneNetKg'])} kg',
                caneType: lot['caneType'] as String?,
                vehicle: null,
                juice: lot['juiceLiters'] == null
                    ? null
                    : '${reportNumber(lot['juiceLiters'])} L',
                margin: lot['calculation'] == null
                    ? null
                    : reportMoney(
                        (lot['calculation'] as Json)['productionMarginRupiah'],
                      ),
                batches: [
                  for (final batch in (lot['batches'] as List).cast<Json>())
                    RecapBatch(
                      number: batch['wokNumber'] as int,
                      shift: null,
                      brix: null,
                      juice: '${reportNumber(batch['quantityMl'])} ml',
                      lime: null,
                      physical: '${reportNumber(batch['physicalWeightKg'])} kg',
                      grade: (batch['grades'] as List)
                          .cast<Json>()
                          .map(
                            (g) =>
                                '${g['code']} · ${reportNumber(g['weightKg'])} kg',
                          )
                          .join(', '),
                      time: formatDate(
                        DateTime.parse(batch['occurredAt'] as String).toLocal(),
                      ),
                      verified: true,
                      code: batch['code'] as String,
                    ),
                ],
              ),
          ], marginTotalOverride: amount('productionMarginRupiah', money: true)),
  );

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}

String reportShare(Object? weight, Object? total) {
  final denominator = double.tryParse('$total') ?? 0;
  final numerator = double.tryParse('$weight') ?? 0;
  return '${demoNumber(denominator == 0 ? 0 : numerator / denominator * 100, decimals: 1)}%';
}

AnalyticsRow _reportRow(Json lot, ReportTab tab) {
  final calculation = lot['calculation'] as Json?;
  final margin = tab == ReportTab.margin;
  return AnalyticsRow(
    lot['supplier'] as String,
    lot['code'] as String,
    calculation == null
        ? '—'
        : margin
        ? reportMoney(calculation['productionMarginRupiah'])
        : '${reportNumber(calculation['finalSugarKg'])} kg',
    calculation == null
        ? '—'
        : '${reportNumber(calculation['rendemenPercent'])}%',
    id: lot['lotId'] as String,
    date: DateTime.parse(lot['receivedAt'] as String).toLocal(),
  );
}
