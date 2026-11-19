import 'package:flutter/foundation.dart';

import '../pekerjaan/review_api.dart';
import 'demo_production.dart';
import '../laporan/connected_reports.dart';

class ConnectedProduction extends ChangeNotifier {
  ConnectedProduction(this.api, this.scope)
    : reports = ConnectedReports(api, scope);

  final ConnectedReports reports;

  final ReviewApi api;
  final FactoryScope scope;
  List<DemoKloter> lots = const [];
  Object? error;
  bool loading = true;
  int _generation = 0;

  Future<void> refresh() async {
    final reportRequest = reports.refresh();
    final generation = ++_generation;
    loading = true;
    error = null;
    lots = const [];
    notifyListeners();
    try {
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
    }
    await reportRequest;
    if (generation != _generation) return;
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
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
    final revision = document?['revisionNumber'] ?? document?['revisionId'];
    final documentId = document?['documentId'];
    return DemoReview([
      DemoField('Status', approved == null ? 'Belum disahkan' : 'Disahkan'),
      ...fields,
      if (documentId != null) DemoField('ID nota', '$documentId'),
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
