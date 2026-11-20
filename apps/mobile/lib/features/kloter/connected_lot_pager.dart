import 'package:flutter/foundation.dart';

import '../pekerjaan/review_api.dart';
import 'connected_production.dart';
import 'demo_production.dart';
import 'kloter_date_filter.dart';

/// One independently filtered view. Counts always describe all matching rows.
class ConnectedLotPager extends ChangeNotifier {
  ConnectedLotPager(
    this.api,
    this.scope, {
    this.synthetic = false,
    this.status,
  });
  final ReviewApi api;
  final FactoryScope scope;
  bool synthetic;
  String? status;
  String search = '';
  String? selectedId;
  KloterDateFilter? date;
  List<DemoKloter> items = const [];
  List<DemoKloter> suggestions = const [];
  Json? counts;
  String? nextCursor;
  Object? error;
  Object? moreError;
  bool loading = false;
  bool loadingMore = false;
  bool initialized = false;
  int _generation = 0;
  int _loadedPages = 1;
  bool _disposed = false;
  bool get hasMore => nextCursor != null;

  Map<String, String> get filters => {
    'synthetic': '$synthetic',
    'searchMode': 'normalized',
    if (search.trim().isNotEmpty && selectedId == null) 'q': search.trim(),
    'lotId': ?selectedId,
    if (date != null) ...{
      'receivedFrom': DateTime(
        date!.range.start.year,
        date!.range.start.month,
        date!.range.start.day,
      ).toUtc().toIso8601String(),
      // Calendar construction preserves the next local midnight across DST.
      'receivedBefore': DateTime(
        date!.range.end.year,
        date!.range.end.month,
        date!.range.end.day + 1,
      ).toUtc().toIso8601String(),
    },
  };

  Future<void> setFilters({
    required String search,
    required String? status,
    required KloterDateFilter? date,
    String? selectedId,
  }) {
    this.search = search;
    this.status = status;
    this.date = date;
    this.selectedId = selectedId;
    return refresh(reset: true);
  }

  Future<void> refresh({bool reset = false}) async {
    if (_disposed) return;
    final generation = ++_generation;
    final pages = reset ? 1 : _loadedPages;
    final base = filters;
    final pageFilters = {...base, 'status': ?status};
    loading = true;
    initialized = true;
    loadingMore = false;
    error = moreError = null;
    if (reset) {
      _loadedPages = 1;
      items = const [];
      counts = null;
      nextCursor = null;
    }
    suggestions = const [];
    notifyListeners();
    try {
      final responses = await Future.wait([
        api.lotCursor(scope, filters: pageFilters),
        api.lotCounts(scope, base),
        if (search.trim().isNotEmpty && selectedId == null)
          api.lotSuggestions(scope, {...pageFilters}..remove('searchMode')),
      ]);
      if (generation != _generation) return;
      final rows = <String, DemoKloter>{};
      var page = responses[0];
      var loadedPages = 1;
      for (var index = 0; index < pages; index++) {
        for (final row in (page['items'] as List).cast<Json>()) {
          rows[row['id'] as String] = connectedLot(row);
        }
        final cursor = page['nextCursor'] as String?;
        if (index + 1 >= pages || cursor == null) break;
        page = await api.lotCursor(scope, filters: pageFilters, after: cursor);
        loadedPages++;
        if (generation != _generation) return;
      }
      final summary = responses[1];
      if (['total', 'open', 'closed'].any((key) => summary[key] is! int)) {
        throw const FormatException('Hitungan kloter tidak lengkap.');
      }
      items = List.unmodifiable(rows.values);
      _loadedPages = loadedPages;
      counts = summary;
      nextCursor = page['nextCursor'] as String?;
      suggestions = responses.length < 3
          ? const []
          : List.unmodifiable(
              (responses[2]['items'] as List).cast<Json>().map(connectedLot),
            );
    } catch (failure) {
      if (generation != _generation) return;
      error = failure;
    }
    if (generation != _generation) return;
    loading = false;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (_disposed || loading || loadingMore || nextCursor == null) return;
    final generation = _generation;
    final cursor = nextCursor!;
    loadingMore = true;
    moreError = null;
    notifyListeners();
    try {
      final page = await api.lotCursor(
        scope,
        filters: {...filters, 'status': ?status},
        after: cursor,
      );
      if (generation != _generation) return;
      final rows = {for (final item in items) item.id!: item};
      for (final row in (page['items'] as List).cast<Json>()) {
        rows[row['id'] as String] = connectedLot(row);
      }
      final next = page['nextCursor'] as String?;
      if (next == cursor) {
        throw const FormatException('Cursor kloter tidak bergerak.');
      }
      items = List.unmodifiable(rows.values);
      _loadedPages++;
      nextCursor = next;
    } catch (failure) {
      if (generation != _generation) return;
      moreError = failure;
    }
    if (generation != _generation) return;
    loadingMore = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
