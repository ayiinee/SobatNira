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

class _ReportSelection {
  _ReportSelection(this.synthetic);
  bool synthetic;
  KloterDateFilter? filter;
  Map<String, String> dimensions = const {};
  DateTime? latestSyntheticReceipt;
}

class ConnectedReports extends ChangeNotifier {
  ConnectedReports(this.api, this.scope, {bool synthetic = false})
    : _selection = _ReportSelection(synthetic),
      _parent = null;
  ConnectedReports._summary(ConnectedReports parent)
    : api = parent.api,
      scope = parent.scope,
      _selection = parent._selection,
      _parent = parent;
  final ReviewApi api;
  final FactoryScope scope;
  final _ReportSelection _selection;
  final ConnectedReports? _parent;
  ConnectedReports? _summaryState;
  bool get _summaryOnly => _parent != null;
  ConnectedReports get summary =>
      _summaryOnly ? this : (_summaryState ??= ConnectedReports._summary(this));
  KloterDateFilter? get filter => _selection.filter;
  set filter(KloterDateFilter? value) => _selection.filter = value;
  Map<String, String> get dimensions => _selection.dimensions;
  bool get narrow =>
      dimensions.containsKey('batchId') || dimensions.containsKey('grade');
  bool get synthetic => _selection.synthetic;
  set synthetic(bool value) => _selection.synthetic = value;
  bool loading = true;
  Object? error;
  Json? data;
  bool detailsRequested = false;
  Future<void>? _detailRequest;
  Future<void> ensureDetails() {
    if (_summaryOnly) return _parent!.ensureDetails();
    if (data != null && data?['view'] != 'summary') {
      detailsRequested = true;
      return Future.value();
    }
    return _detailRequest ?? refresh();
  }

  int _generation = 0;
  DateTime? get _latestSyntheticReceipt => _selection.latestSyntheticReceipt;
  set _latestSyntheticReceipt(DateTime? value) =>
      _selection.latestSyntheticReceipt = value;
  DateTime get filterToday =>
      (synthetic ? _latestSyntheticReceipt : null) ?? DateTime.now();
  List<Json> get lots => (data?['items'] as List? ?? const []).cast<Json>();
  List<Json> get grades => (data?['grades'] as List? ?? const []).cast<Json>();
  Json get totals => data?['totals'] as Json? ?? const {};
  bool get provisional =>
      data?['provisional'] == true ||
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
      data == null || totals[key] == null
      ? '—'
      : money
      ? reportMoney(totals[key])
      : '${reportNumber(totals[key])}$unit';

  Future<void> refresh({Future<Json>? unfiltered, bool? summaryOnly}) {
    final summaries = summaryOnly ?? _summaryOnly;
    final request = _refresh(unfiltered: unfiltered, summaryOnly: summaries);
    if (!summaries) {
      _detailRequest = request;
      request.whenComplete(() {
        if (identical(_detailRequest, request)) _detailRequest = null;
      });
    }
    return request;
  }

  Future<void> refreshHome() {
    if (_summaryOnly) return refresh();
    _generation++;
    _detailRequest = null;
    data = null;
    error = null;
    loading = false;
    detailsRequested = false;
    notifyListeners();
    return summary.refresh();
  }

  void _invalidateSummary() {
    _generation++;
    data = null;
    error = null;
    loading = true;
    notifyListeners();
  }

  void _acceptSummary(Json result, {required bool provisional}) {
    _generation++;
    data = {
      ...result,
      'view': 'summary',
      'items': <Json>[],
      'provisional': provisional,
    };
    error = null;
    loading = false;
    notifyListeners();
  }

  Future<void> _refresh({
    Future<Json>? unfiltered,
    required bool summaryOnly,
  }) async {
    if (!_summaryOnly) _summaryState?._invalidateSummary();
    if (!summaryOnly) detailsRequested = true;
    final generation = ++_generation;
    loading = true;
    error = null;
    data = null;
    notifyListeners();
    try {
      final selected = filter;
      final preset = selected != null && selected.period != KloterPeriod.custom;
      if (synthetic && preset && _latestSyntheticReceipt == null) {
        final baseline = await api.productionReport(
          scope,
          synthetic: true,
          summaryOnly: true,
        );
        if (generation != _generation) return;
        _latestSyntheticReceipt = _latestReceipt(baseline);
      }
      final effective = preset
          ? KloterDateFilter.preset(selected.period, today: filterToday)
          : selected;
      final range = effective?.range;
      final result =
          await (unfiltered ??
              api.productionReport(
                scope,
                synthetic: synthetic,
                summaryOnly: summaryOnly,
                selection: dimensions,
                from: range?.start,
                before: range == null
                    ? null
                    : DateTime(
                        range.end.year,
                        range.end.month,
                        range.end.day + 1,
                      ),
              ));
      if (generation != _generation) return;
      // Treat a malformed response as unavailable, never as an empty zero report.
      if (result['items'] is! List ||
          result['grades'] is! List ||
          result['totals'] is! Map) {
        throw const FormatException('Laporan tidak lengkap.');
      }
      if (synthetic && range == null) {
        _latestSyntheticReceipt = _latestReceipt(result);
      }
      filter = effective;
      data = result;
      if (!_summaryOnly) {
        _summaryState?._acceptSummary(result, provisional: provisional);
      }
    } catch (failure) {
      if (generation != _generation) return;
      data = null;
      error = failure;
      // Detail limits do not make the independently available home totals fail.
      if (!summaryOnly && _summaryState != null) await _summaryState!.refresh();
    }
    if (generation != _generation) return;
    loading = false;
    notifyListeners();
  }

  DateTime? _latestReceipt(Json report) {
    if (report['latestReceivedAt'] case final String latest) {
      return DateTime.parse(latest).toLocal();
    }
    DateTime? latest;
    for (final lot in (report['items'] as List).cast<Json>()) {
      final received = lot['receivedAt'];
      final date = received is String ? DateTime.tryParse(received) : null;
      if (date != null && (latest == null || date.isAfter(latest))) {
        latest = date;
      }
    }
    return latest?.toLocal();
  }

  Future<void> setFilter(KloterDateFilter? value) {
    if (_summaryOnly) return _parent!.setFilter(value);
    filter = value;
    return refresh();
  }

  Future<void> setSynthetic(bool value) {
    if (_summaryOnly) return _parent!.setSynthetic(value);
    synthetic = value;
    _selection.dimensions = const {};
    return detailsRequested ? refresh() : refreshHome();
  }

  Future<void> setDimensions(Map<String, String> value) {
    if (_summaryOnly) return _parent!.setDimensions(value);
    _selection.dimensions = Map.unmodifiable(value);
    return refresh();
  }

  Future<Json> selectionPage(int offset) {
    final range = filter?.range;
    final end = range?.end;
    return api.reportDetailPage(
      scope,
      synthetic: synthetic,
      offset: offset,
      from: range?.start,
      before: end == null ? null : DateTime(end.year, end.month, end.day + 1),
    );
  }

  PrintableReport printable(PrintableReportKind kind) => PrintableReport(
    kind: kind,
    factory: scope.factoryName,
    period: period,
    synthetic: synthetic,
    connected: true,
    provisional: provisional,
    scopeNote: narrow
        ? 'Biaya dan margin tidak tersedia untuk filter batch atau grade.'
        : null,
    totalDisplayOverride: amount(
      kind == PrintableReportKind.profit
          ? 'productionMarginRupiah'
          : 'finalSugarKg',
      money: kind == PrintableReportKind.profit,
      unit: kind == PrintableReportKind.production ? ' kg' : '',
    ),
    rows: [
      for (final lot in lots)
        if (lot['calculation'] != null ||
            (kind != PrintableReportKind.profit &&
                lot['filteredSugarKg'] != null))
          _reportRow(
            lot,
            kind == PrintableReportKind.profit
                ? ReportTab.margin
                : ReportTab.production,
          ),
    ],
    recap: kind == PrintableReportKind.profit
        ? null
        : ProductionRecap(
            [
              for (final lot in lots)
                RecapKloter(
                  id: lot['lotId'] as String,
                  code: lot['code'] as String,
                  supplier: lot['supplier'] as String,
                  date: DateTime.parse(lot['receivedAt'] as String).toLocal(),
                  sugar: lot['filteredSugarKg'] != null
                      ? '${reportNumber(lot['filteredSugarKg'])} kg'
                      : lot['calculation'] == null
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
                          (lot['calculation']
                              as Json)['productionMarginRupiah'],
                        ),
                  batches: [
                    for (final batch in (lot['batches'] as List).cast<Json>())
                      RecapBatch(
                        number: batch['wokNumber'] as int,
                        shift: null,
                        brix: null,
                        juice: '${reportNumber(batch['quantityMl'])} ml',
                        lime: null,
                        physical:
                            '${reportNumber(batch['physicalWeightKg'])} kg',
                        grade: (batch['grades'] as List)
                            .cast<Json>()
                            .map(
                              (g) =>
                                  '${g['code']} · ${reportNumber(g['weightKg'])} kg',
                            )
                            .join(', '),
                        time: formatDate(
                          DateTime.parse(
                            batch['occurredAt'] as String,
                          ).toLocal(),
                        ),
                        verified: true,
                        code: batch['code'] as String,
                      ),
                  ],
                ),
            ],
            marginTotalOverride: amount('productionMarginRupiah', money: true),
            batchCountOverride: totals['batchCount'] as int?,
          ),
  );

  @override
  void dispose() {
    _generation++;
    _summaryState?.dispose();
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
    !margin && lot['filteredSugarKg'] != null
        ? '${reportNumber(lot['filteredSugarKg'])} kg'
        : calculation == null
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
