import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:sobatnira/features/kloter/connected_lot_pager.dart';
import 'package:sobatnira/features/kloter/kloter_list_page.dart';
import 'package:sobatnira/features/kloter/kloter_date_filter.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';

const base = String.fromEnvironment('PRODUCTION_TEST_API');
const tenant = String.fromEnvironment('PRODUCTION_TEST_TENANT');
const factory = String.fromEnvironment('PRODUCTION_TEST_FACTORY');

class LocalHttp extends HttpOverrides {}

void main() {
  testWidgets(
    'Flutter cursor and badge agree with NestJS/PostgreSQL across filters and mutations',
    (tester) async {
      expect(Uri.parse(base).host, '127.0.0.1');
      final api = ReviewApi(
        'fixture-admin',
        baseUrl: base,
        client: IOClient(
          HttpOverrides.runWithHttpOverrides(HttpClient.new, LocalHttp()),
        ),
      );
      final scope = FactoryScope.fromJson({
        'tenantId': tenant,
        'factoryId': factory,
        'tenantName': 'Synthetic',
        'factoryName': 'Synthetic',
        'role': 'admin',
      });
      final pager = ConnectedLotPager(api, scope);
      addTearDown(pager.dispose);
      addTearDown(api.close);
      await tester.binding.setSurfaceSize(const Size(430, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(
        () => pager.setFilters(search: 'PAG-', status: null, date: null),
      );
      expect(pager.error, isNull);
      expect(pager.items.length, 30);
      expect(pager.counts, {'total': 65, 'open': 49, 'closed': 16});
      final firstIds = pager.items.map((row) => row.id).toSet();
      await tester.runAsync(pager.loadMore);
      expect(pager.items.length, 60);
      expect(
        pager.items.map((row) => row.id).toSet().containsAll(firstIds),
        true,
      );
      await tester.runAsync(pager.loadMore);
      expect(pager.items.length, 65);
      expect(pager.hasMore, false);
      expect(pager.items.map((row) => row.id).toSet().length, 65);
      await tester.runAsync(
        () => pager.setFilters(search: 'pag 0001', status: null, date: null),
      );
      expect(pager.suggestions.single.code, 'PAG-0001');
      expect(pager.items.single.code, 'PAG-0001');
      final id = pager.items.single.id!;
      await tester.runAsync(
        () => pager.setFilters(
          search: '',
          selectedId: id,
          status: null,
          date: null,
        ),
      );
      expect(pager.items.single.id, id);
      expect(pager.counts?['total'], 1);
      final received = DateTime.parse(
        pager.items.single.record!['receivedAt'] as String,
      ).toLocal();
      final day = DateTime(received.year, received.month, received.day);
      await tester.runAsync(
        () => pager.setFilters(
          search: 'PAG-',
          status: 'closed',
          date: KloterDateFilter(
            KloterPeriod.custom,
            DateTimeRange(start: day, end: day),
          ),
        ),
      );
      expect(pager.error, isNull);
      expect(pager.counts?['total'], 24);
      expect(pager.counts?['closed'], 6);
      expect(pager.items.length, 6);
      expect(
        pager.items.every(
          (row) => row.date == day && row.record?['status'] == 'closed',
        ),
        true,
      );
      final reopenedId = pager.items.first.id!;
      final closure = await tester.runAsync(
        () => api.lotClosure(scope, reopenedId),
      );
      await tester.runAsync(
        () => api.changeLotClosure(
          scope,
          reopenedId,
          closureId: closure!['closureId'] as String,
          reason: 'Synthetic pagination reopening',
        ),
      );
      await tester.runAsync(pager.refresh);
      expect(pager.counts?['closed'], 5);
      expect(pager.items.any((row) => row.id == reopenedId), false);
      await tester.runAsync(
        () => pager.setFilters(search: '', status: 'open', date: null),
      );
      final total = pager.counts!['total'] as int;
      final supplier = await tester.runAsync(
        () => api.saveCatalog(scope, ProductionCatalog.suppliers, {
          'name': 'Pagination fixture supplier',
        }),
      );
      await tester.runAsync(
        () => api.saveLot(scope, {
          'supplierId': supplier!['id'],
          'displayCode': 'UI-NEW',
          'receivedAt': DateTime.fromMillisecondsSinceEpoch(
            DateTime.now().millisecondsSinceEpoch,
            isUtc: true,
          ).toIso8601String(),
        }),
      );
      await tester.runAsync(pager.refresh);
      expect(pager.counts!['total'], total + 1);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: pager,
              builder: (_, _) => KloterListPage(
                pager: pager,
                kloter: const [],
                onOpenKloter: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('${pager.counts!['open']}'), findsOneWidget);
      // A separate factory scope must never inherit this pager's rows or cursors.
      final stranger = ConnectedLotPager(
        api,
        FactoryScope.fromJson({
          'tenantId': tenant,
          'factoryId': '00000000-0000-4000-8000-000000000000',
          'factoryName': 'Other',
          'tenantName': 'Synthetic',
        }),
      );
      await tester.runAsync(stranger.refresh);
      expect(stranger.items, isEmpty);
      expect(stranger.error, isNotNull);
      stranger.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: base.isEmpty,
  );
}
