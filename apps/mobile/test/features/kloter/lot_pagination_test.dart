import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/features/kloter/connected_lot_pager.dart';
import 'package:sobatnira/features/kloter/kloter_date_filter.dart';
import 'package:sobatnira/features/kloter/kloter_list_page.dart';
import 'package:sobatnira/features/kloter/demo_production.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';

final scope = FactoryScope.fromJson({
  'tenantId': 'tenant',
  'factoryId': 'A',
  'tenantName': 'Tenant',
  'factoryName': 'A',
  'role': 'admin',
});
Json lot(String id, {String status = 'open', String? date}) => {
  'id': id,
  'displayCode': id,
  'supplierName': 'Pemasok',
  'status': status,
  'receivedAt': date ?? DateTime(2026, 11, 20, 10).toUtc().toIso8601String(),
};
http.Response json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  testWidgets(
    'connected pagination badge and controls fit narrow enlarged text',
    (tester) async {
      final api = ReviewApi(
        'token',
        client: MockClient(
          (r) async => r.url.path.endsWith('/counts')
              ? json({'total': 250, 'open': 125, 'closed': 125})
              : json({
                  'items': [lot('LONG-KLOTER-CODE-2026-EXAMPLE')],
                  'nextCursor': 'next',
                }),
        ),
      );
      final pager = ConnectedLotPager(api, scope);
      addTearDown(pager.dispose);
      addTearDown(api.close);
      await pager.refresh();
      await tester.binding.setSurfaceSize(const Size(320, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: KloterListPage(
              pager: pager,
              kloter: const [],
              onOpenKloter: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('125'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'loading more retains cards and scroll position through failure and retry',
    (tester) async {
      var fail = true;
      final api = ReviewApi(
        'token',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/counts')) {
            return json({'total': 31, 'open': 31, 'closed': 0});
          }
          if (r.url.queryParameters.containsKey('after')) {
            if (fail) {
              return json({'message': 'offline'}, 503);
            }
            return json({
              'items': [lot('LAST')],
              'nextCursor': null,
            });
          }
          return json({
            'items': List.generate(30, (i) => lot('ROW-$i')),
            'nextCursor': 'next',
          });
        }),
      );
      final pager = ConnectedLotPager(api, scope);
      addTearDown(pager.dispose);
      addTearDown(api.close);
      await pager.refresh();
      await tester.binding.setSurfaceSize(const Size(430, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
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
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      scroll.jumpTo(400);
      await tester.pumpAndSettle();
      final position = scroll.offset;
      await pager.loadMore();
      await tester.pumpAndSettle();
      expect(pager.items.length, 30);
      expect(scroll.offset, position);
      expect(pager.moreError, isNotNull);
      fail = false;
      await pager.loadMore();
      await tester.pumpAndSettle();
      expect(pager.items.length, 31);
      expect(scroll.offset, position);
      expect(pager.hasMore, false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'fetches one page, full counts, no duplicate load and retries the same cursor',
    () async {
      final requests = <Uri>[];
      final delayed = Completer<http.Response>();
      var fail = true;
      final api = ReviewApi(
        'token',
        client: MockClient((r) async {
          requests.add(r.url);
          expect(r.headers['authorization'], 'Bearer token');
          if (r.url.path.endsWith('/counts')) {
            return json({'total': 62, 'open': 41, 'closed': 21});
          }
          if (r.url.queryParameters['after'] == 'next') {
            if (fail) return json({'message': 'try again'}, 503);
            return delayed.future;
          }
          return json({
            'items': List.generate(30, (i) => lot('A-$i')),
            'nextCursor': 'next',
          });
        }),
      );
      final pager = ConnectedLotPager(api, scope);
      addTearDown(pager.dispose);
      addTearDown(api.close);
      await pager.refresh();
      expect(requests.length, 2);
      expect(pager.items.length, 30);
      expect(pager.counts?['open'], 41);
      await pager.loadMore();
      expect(pager.moreError, isNotNull);
      expect(pager.items.length, 30);
      fail = false;
      final pending = pager.loadMore();
      await pager.loadMore();
      await Future<void>.delayed(Duration.zero);
      expect(
        requests.where((r) => r.queryParameters['after'] == 'next').length,
        2,
      );
      delayed.complete(
        json({
          'items': [lot('A-29'), lot('A-30')],
          'nextCursor': null,
        }),
      );
      await pending;
      expect(pager.items.length, 31);
      expect(pager.moreError, isNull);
      expect(pager.hasMore, false);
      await pager.loadMore();
      expect(requests.where((r) => r.path.endsWith('/counts')).length, 1);
      final before = requests.length;
      await pager.refresh();
      // Refresh only the two pages the user already opened, plus counts.
      expect(requests.length - before, 3);
    },
  );

  test(
    'filters reset cursors, ignore late pages, and use exclusive next local midnight',
    () async {
      final stale = Completer<http.Response>();
      final requests = <Uri>[];
      final api = ReviewApi(
        'token',
        client: MockClient((r) async {
          requests.add(r.url);
          if (r.url.path.endsWith('/counts')) {
            return json({'total': 5, 'open': 3, 'closed': 2});
          }
          if (r.url.path.endsWith('/suggestions')) {
            return json({
              'items': [lot('EXACT')],
            });
          }
          if (r.url.queryParameters['after'] != null) return stale.future;
          return json({
            'items': [lot(r.url.queryParameters['q'] ?? 'old')],
            'nextCursor': 'next',
          });
        }),
      );
      final pager = ConnectedLotPager(api, scope);
      addTearDown(pager.dispose);
      addTearDown(api.close);
      await pager.refresh();
      final old = pager.loadMore();
      final date = KloterDateFilter(
        KloterPeriod.custom,
        DateTimeRange(
          start: DateTime(2026, 11, 19),
          end: DateTime(2026, 11, 20),
        ),
      );
      await pager.setFilters(search: 'EXACT', status: 'closed', date: date);
      stale.complete(
        json({
          'items': [lot('stale')],
          'nextCursor': null,
        }),
      );
      await old;
      expect(pager.items.single.id, 'EXACT');
      expect(pager.loadingMore, false);
      expect(pager.suggestions.single.code, 'EXACT');
      final counts = requests.lastWhere((r) => r.path.endsWith('/counts'));
      expect(counts.queryParameters.containsKey('status'), false);
      expect(
        counts.queryParameters['receivedFrom'],
        DateTime(2026, 11, 19).toUtc().toIso8601String(),
      );
      expect(
        counts.queryParameters['receivedBefore'],
        DateTime(2026, 11, 21).toUtc().toIso8601String(),
      );
      final page = requests.lastWhere((r) => r.path.endsWith('/lots'));
      expect(page.queryParameters['status'], 'closed');
      expect(page.queryParameters.containsKey('after'), false);
      await pager.setFilters(
        search: 'EXACT',
        selectedId: 'uuid-selected',
        status: null,
        date: null,
      );
      expect(pager.filters['lotId'], 'uuid-selected');
      expect(pager.filters.containsKey('q'), false);
    },
  );

  test(
    'failure retains loaded rows and disposal suppresses late notifications',
    () async {
      var fail = false;
      final delayed = Completer<http.Response>();
      final api = ReviewApi(
        'token',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/counts')) {
            return json({'total': 1, 'open': 1, 'closed': 0});
          }
          if (fail) return delayed.future;
          return json({
            'items': [lot('saved')],
            'nextCursor': null,
          });
        }),
      );
      addTearDown(api.close);
      final pager = ConnectedLotPager(api, scope);
      await pager.refresh();
      fail = true;
      final pending = pager.refresh();
      pager.dispose();
      delayed.complete(json({'message': 'offline'}, 503));
      await pending;
      expect(pager.items.single.id, 'saved');
    },
  );

  testWidgets(
    'connected list uses server badge, groups dates and searches outside loaded pages',
    (tester) async {
      final requests = <Uri>[];
      final api = ReviewApi(
        'token',
        client: MockClient((r) async {
          requests.add(r.url);
          if (r.url.path.endsWith('/counts')) {
            return json({'total': 200, 'open': 125, 'closed': 75});
          }
          if (r.url.path.endsWith('/suggestions')) {
            return json({
              'items': [lot('REMOTE-EXACT')],
            });
          }
          final q = r.url.queryParameters;
          return json({
            'items': [
              lot(
                q['lotId'] ?? q['q'] ?? 'FIRST',
                status: q['status'] ?? 'open',
              ),
            ],
            'nextCursor': null,
          });
        }),
      );
      final pager = ConnectedLotPager(api, scope);
      addTearDown(pager.dispose);
      addTearDown(api.close);
      await tester.binding.setSurfaceSize(const Size(430, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
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
      expect(find.text('125'), findsOneWidget);
      expect(find.text('FIRST'), findsOneWidget);
      expect(find.text(formatDate(DateTime(2026, 11, 20))), findsWidgets);
      await tester.enterText(find.byType(TextField), 'REMOTE');
      await tester.pumpAndSettle();
      expect(
        requests.any(
          (r) =>
              r.path.endsWith('/suggestions') &&
              r.queryParameters['q'] == 'REMOTE',
        ),
        true,
      );
      expect(find.text('REMOTE-EXACT'), findsOneWidget);
      await tester.tap(find.text('REMOTE-EXACT'));
      await tester.pumpAndSettle();
      expect(
        requests
            .lastWhere((r) => r.path.endsWith('/lots'))
            .queryParameters['lotId'],
        'REMOTE-EXACT',
      );
      await tester.tap(find.text('Tuntas'));
      await tester.pumpAndSettle();
      expect(
        requests
            .lastWhere((r) => r.path.endsWith('/lots'))
            .queryParameters['status'],
        'closed',
      );
      expect(find.text('125'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
