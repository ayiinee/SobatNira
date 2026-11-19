import 'dart:async';

import 'package:flutter/foundation.dart';

import '../pekerjaan/review_api.dart';
import 'demo_production.dart';
import '../laporan/connected_reports.dart';

class ConnectedProduction extends ChangeNotifier {
  ConnectedProduction(
    this.api,
    this.scope, {
    bool synthetic = false,
    this.onSyntheticChanged,
  }) : reports = ConnectedReports(api, scope, synthetic: synthetic),
       _synthetic = synthetic {
    reports.addListener(_sourceChanged);
  }

  final ConnectedReports reports;

  final ReviewApi api;
  final FactoryScope scope;
  final ValueChanged<bool>? onSyntheticChanged;
  List<DemoKloter> lots = const [];
  Object? error;
  bool loading = true;
  int _generation = 0;
  bool _synthetic;

  void _sourceChanged() {
    if (_synthetic == reports.synthetic) return;
    _synthetic = reports.synthetic;
    onSyntheticChanged?.call(_synthetic);
    unawaited(_refreshLots());
  }

  Future<void> refresh() async {
    await Future.wait([reports.refresh(), _refreshLots()]);
  }

  Future<void> _refreshLots() async {
    final generation = ++_generation;
    loading = true;
    error = null;
    lots = const [];
    notifyListeners();
    try {
      if (_synthetic) {
        // The list endpoint summarizes official records. Use the unfiltered
        // synthetic report as the index and load synthetic lot summaries.
        final report = await api.productionReport(scope, synthetic: true);
        final items = (report['items'] as List).cast<Json>();
        final result = <DemoKloter>[];
        for (var start = 0; start < items.length; start += 6) {
          if (generation != _generation) return;
          final details = await Future.wait([
            for (final item in items.skip(start).take(6))
              api.lot(scope, item['lotId'] as String, synthetic: true),
          ]);
          result.addAll(details.map(connectedLot));
        }
        if (generation == _generation) lots = List.unmodifiable(result);
        return;
      }
      final rows = <String, DemoKloter>{};
      var offset = 0;
      while (true) {
        final page = await api.lots(
          scope,
          offset: offset,
          search: '',
          limit: 100,
          includeSummary: true,
        );
        if (generation != _generation) return;
        final items = (page['items'] as List).cast<Json>();
        for (final item in items) {
          rows[item['id'] as String] = connectedLot(item);
        }
        offset += items.length;
        if (items.isEmpty || offset >= (page['total'] as int)) break;
      }
      lots = List.unmodifiable(rows.values);
    } catch (failure) {
      if (generation != _generation) return;
      error = failure;
    } finally {
      if (generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    reports.removeListener(_sourceChanged);
    reports.dispose();
    super.dispose();
  }
}

DemoKloter connectedLot(Json row) {
  final suppliedCode = row['displayCode'] as String?;
  final id = row['id'] as String;
  final received = DateTime.parse(row['receivedAt'] as String).toLocal();
  final date = DateTime(received.year, received.month, received.day);
  final code = (suppliedCode?.isNotEmpty ?? false) ? suppliedCode! : id;
  final intake = row['intake'] as Json?;
  final milling = row['milling'] as Json?;
  DemoReview review(Json? approved, List<DemoField> fields) {
    final document = approved?['document'] as Json?;
    final revision = document?['revisionNumber'];
    return DemoReview([
      DemoField('Status', approved == null ? 'Belum disahkan' : 'Disahkan'),
      ...fields,
      if (revision != null) DemoField('Revisi tercatat', '$revision'),
    ], verified: approved != null);
  }

  return DemoKloter.connected(
    record: row,
    code: code,
    date: date,
    intake: review(intake, [
      DemoField('Pemasok', row['supplierName'] as String),
      if (row['caneTypeCode'] case final String type)
        DemoField('Jenis tebu', type),
    ]),
    milling: review(milling, [DemoField('Kloter sumber', code)]),
  );
}
