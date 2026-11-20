import 'dart:async';

import 'package:flutter/foundation.dart';

import '../pekerjaan/review_api.dart';
import 'demo_production.dart';
import 'connected_lot_pager.dart';
import '../laporan/connected_reports.dart';

class ConnectedProduction extends ChangeNotifier {
  ConnectedProduction(
    this.api,
    this.scope, {
    bool synthetic = false,
    this.onSyntheticChanged,
  }) : reports = ConnectedReports(api, scope, synthetic: synthetic),
       home = ConnectedLotPager(
         api,
         scope,
         synthetic: synthetic,
         status: 'open',
       ),
       browser = ConnectedLotPager(api, scope, synthetic: synthetic),
       _synthetic = synthetic {
    reports.addListener(_sourceChanged);
    home.addListener(notifyListeners);
    browser.addListener(notifyListeners);
  }
  final ReviewApi api;
  final FactoryScope scope;
  final ConnectedReports reports;
  final ConnectedLotPager home;
  final ConnectedLotPager browser;
  final ValueChanged<bool>? onSyntheticChanged;
  bool _synthetic;
  bool _disposed = false;
  List<DemoKloter> get lots => home.items;
  bool get loading => home.loading;
  Object? get error => home.error;

  void _sourceChanged() {
    if (_synthetic == reports.synthetic) return;
    _synthetic = reports.synthetic;
    onSyntheticChanged?.call(_synthetic);
    home.synthetic = browser.synthetic = _synthetic;
    browser.search = '';
    browser.selectedId = null;
    browser.date = null;
    browser.status = null;
    unawaited(home.refresh(reset: true));
    // Clear both sources immediately, including an unopened/offstage list.
    unawaited(browser.refresh(reset: true));
  }

  Future<void> refresh() => _disposed
      ? Future.value()
      : Future.wait([
          reports.refresh(summaryOnly: !reports.detailsRequested),
          home.refresh(),
          if (browser.initialized) browser.refresh(),
        ]);

  @override
  void dispose() {
    _disposed = true;
    reports.removeListener(_sourceChanged);
    home.removeListener(notifyListeners);
    browser.removeListener(notifyListeners);
    home.dispose();
    browser.dispose();
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
      DemoField('Tanggal masuk', formatDate(date)),
      DemoField('Pengirim', row['supplierName'] as String),
      if (row['caneTypeCode'] case final String type)
        DemoField('Jenis tebu', type),
    ]),
    milling: review(milling, [DemoField('Kloter sumber', code)]),
  );
}
