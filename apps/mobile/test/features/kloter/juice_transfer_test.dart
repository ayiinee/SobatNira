import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/features/kloter/juice_transfer_page.dart';
import 'package:sobatnira/features/kloter/juice_volume.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';
import 'package:sobatnira/sobatnira_ui.dart';

final scope = FactoryScope.fromJson({
  'tenantId': 'tenant',
  'tenantName': 'Tenant',
  'factoryId': 'factory',
  'factoryName': 'Pabrik Uji',
});
const root = '/tenants/tenant/factories/factory/lots';
Json balance({String available = '50000'}) => {
  'availableMl': available,
  'origins': [
    {'originLotId': 'source', 'availableMl': available},
    {'originLotId': 'origin-x', 'availableMl': '20000.000000000001'},
    {'originLotId': 'empty', 'availableMl': '0'},
  ],
};
Json lot({bool closed = false}) => {
  'id': 'source',
  'displayCode': 'SUMBER',
  'status': closed ? 'closed' : 'open',
};
http.Response jsonResponse(Json data, [int status = 200]) =>
    http.Response(jsonEncode(data), status);

Future<void> press(
  WidgetTester tester,
  String text, {
  bool tooltip = false,
}) async {
  final finder = (tooltip ? find.byTooltip(text) : find.text(text)).last;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> mount(
  WidgetTester tester,
  ReviewApi api, {
  ValueChanged<NiraTab>? onNavigate,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      home: JuiceTransferPage(
        api: api,
        scope: scope,
        lotId: 'source',
        onNavigate: onNavigate,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester) async {
  await press(tester, 'Kloter tujuan');
  await press(tester, 'TUJUAN');
}

http.Response read(http.Request request) {
  if (request.url.path.endsWith('/origin-x')) {
    return jsonResponse({'id': 'origin-x', 'displayCode': 'ASAL-X'});
  }
  if (request.url.path == root) {
    return jsonResponse({
      'items': [
        {
          'id': 'destination',
          'displayCode': 'TUJUAN',
          'supplierName': 'Pemasok Uji',
        },
      ],
      'limit': 20,
      'offset': 0,
      'total': 1,
    });
  }
  if (request.url.path.endsWith('/availability')) {
    return jsonResponse(balance());
  }
  return jsonResponse(lot());
}

void main() {
  test(
    'liter conversion and comparison preserve decimal strings beyond floating point precision',
    () {
      expect(
        litersToMilliliters('20,000000000000000001'),
        '20000.000000000000001',
      );
      expect(litersToMilliliters('0.0001'), '0.1');
      expect(
        litersToMilliliters('9007199254740993.123456'),
        '9007199254740993123.456',
      );
      expect(litersToMilliliters('1.2300'), '1230');
      expect(
        millilitersToLiters('20000.000000000000001'),
        '20.000000000000000001',
      );
      expect(millilitersToLiters('0.1'), '0.0001');
      expect(
        compareJuiceVolumes('9007199254740993.1', '9007199254740993.09'),
        1,
      );
      expect(compareJuiceVolumes('1.00', '1'), 0);
      for (final invalid in [
        '',
        '0',
        '0.000',
        '-1',
        '1e3',
        '1.000,5',
        '01',
        '1/2',
        'Infinity',
      ]) {
        expect(litersToMilliliters(invalid), isNull, reason: invalid);
      }
      expect(litersToMilliliters('9' * 64), isNull);
    },
  );

  testWidgets(
    'transfer selects an origin and a paginated destination and posts an exact volume',
    (tester) async {
      final writes = <http.Request>[];
      final pages = <Uri>[];
      final api = ReviewApi(
        'fixture',
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer fixture');
          expect(request.url.path, startsWith(root));
          if (request.method == 'POST') {
            writes.add(request);
            return jsonResponse({
              ...jsonDecode(request.body) as Json,
              'createdBy': 'admin',
            }, 201);
          }
          if (request.url.path == root) {
            pages.add(request.url);
            final next = request.url.queryParameters['offset'] == '20';
            return jsonResponse({
              'items': next
                  ? [
                      {
                        'id': 'destination',
                        'displayCode': 'TUJUAN',
                        'supplierName': 'Pemasok Uji',
                      },
                    ]
                  : [
                      {
                        'id': 'source',
                        'displayCode': 'SUMBER',
                        'supplierName': 'Pemasok Uji',
                      },
                    ],
              'limit': 20,
              'offset': next ? 20 : 0,
              'total': 21,
            });
          }
          if (request.url.path.endsWith('/origin-x')) {
            return jsonResponse({'id': 'origin-x', 'displayCode': 'ASAL-X'});
          }
          return request.url.path.endsWith('/availability')
              ? jsonResponse(balance())
              : jsonResponse(lot());
        }),
      );
      await mount(tester, api);
      await press(tester, 'Nira kloter ini');
      await press(tester, 'Asal ASAL-X');
      expect(find.text('20.000000000000001 L'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '21');
      await press(tester, 'Kirim transfer');
      expect(
        find.text('Volume melebihi nira tersedia dari sumber ini.'),
        findsOneWidget,
      );
      expect(writes, isEmpty);
      await press(tester, 'Kloter tujuan');
      expect(find.text('SUMBER'), findsNothing);
      await press(tester, 'Berikutnya', tooltip: true);
      expect(pages.last.queryParameters['offset'], '20');
      await tester.enterText(find.byType(TextField), 'TUJUAN & B');
      await tester.tap(find.byTooltip('Cari kloter tujuan'));
      await tester.pumpAndSettle();
      expect(pages.last.queryParameters['q'], 'TUJUAN & B');
      expect(pages.last.queryParameters['offset'], '0');
      await press(tester, 'Berikutnya', tooltip: true);
      await press(tester, 'TUJUAN');
      await tester.enterText(find.byType(TextFormField), '20,000000000000001');
      await press(tester, 'Kirim transfer');
      expect(writes, hasLength(1));
      expect(writes.single.url.path, '$root/source/juice/transfers');
      final payload = jsonDecode(writes.single.body) as Json;
      expect(payload['quantityMl'], '20000.000000000001');
      expect(payload['originLotId'], 'origin-x');
      expect(payload['toLotId'], 'destination');
      expect(
        payload['requestId'],
        matches(
          RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
          ),
        ),
      );
      expect(payload.keys.toSet(), {
        'quantityMl',
        'originLotId',
        'toLotId',
        'requestId',
      });
      expect(find.text('Transfer tercatat'), findsOneWidget);
      expect(api.pendingTransfer(scope, 'source'), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );

  testWidgets(
    'a lost response survives reopening the form and retries the same request',
    (tester) async {
      final writes = <Json>[];
      final api = ReviewApi(
        'fixture',
        client: MockClient((request) async {
          if (request.method == 'POST') {
            writes.add(jsonDecode(request.body) as Json);
            if (writes.length == 1) {
              throw TimeoutException('Synthetic lost response');
            }
            return jsonResponse({...writes.last, 'createdBy': 'admin'}, 201);
          }
          return read(request);
        }),
      );
      await mount(tester, api);
      await choose(tester);
      await tester.enterText(find.byType(TextFormField), '10');
      await press(tester, 'Kirim transfer');
      expect(
        find.textContaining('Hasil transfer belum terkonfirmasi.'),
        findsOneWidget,
      );
      expect(find.byType(TextFormField), findsNothing);
      expect(api.pendingTransfer(scope, 'source'), isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester, api);
      expect(find.text('Coba lagi transfer yang sama'), findsOneWidget);
      expect(writes, hasLength(1));
      await press(tester, 'Coba lagi transfer yang sama');
      expect(writes, hasLength(2));
      expect(writes[0], writes[1]);
      expect(find.text('Transfer tercatat'), findsOneWidget);
      expect(api.pendingTransfer(scope, 'source'), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );

  testWidgets(
    'a definitive conflict refreshes the source and allows a new corrected request',
    (tester) async {
      final writes = <Json>[];
      final api = ReviewApi(
        'fixture',
        client: MockClient((request) async {
          if (request.method == 'POST') {
            writes.add(jsonDecode(request.body) as Json);
            return writes.length == 1
                ? jsonResponse({}, 409)
                : jsonResponse({...writes.last, 'createdBy': 'admin'}, 201);
          }
          return read(request);
        }),
      );
      await mount(tester, api);
      await choose(tester);
      await tester.enterText(find.byType(TextFormField), '10');
      await press(tester, 'Kirim transfer');
      expect(find.textContaining('Transfer ditolak.'), findsOneWidget);
      expect(api.pendingTransfer(scope, 'source'), isNull);
      await tester.enterText(find.byType(TextFormField), '5');
      await press(tester, 'Kirim transfer');
      expect(writes[0]['requestId'], isNot(writes[1]['requestId']));
      expect(writes[1]['quantityMl'], '5000');
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );

  testWidgets(
    'a pending POST cannot be submitted twice or navigated away from',
    (tester) async {
      final pending = Completer<http.Response>();
      var posts = 0;
      var navigations = 0;
      final api = ReviewApi(
        'fixture',
        client: MockClient((request) async {
          if (request.method == 'POST') {
            posts++;
            return pending.future;
          }
          return read(request);
        }),
      );
      await mount(tester, api, onNavigate: (_) => navigations++);
      await choose(tester);
      await tester.enterText(find.byType(TextFormField), '1');
      await tester.ensureVisible(find.text('Kirim transfer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kirim transfer'));
      await tester.pump();
      expect(posts, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Coba lagi transfer yang sama'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
      await tester.tap(find.bySemanticsLabel('Laporan'));
      await tester.pump();
      expect(navigations, 0);
      final draft = api.pendingTransfer(scope, 'source')!;
      pending.complete(
        jsonResponse({...draft.body, 'createdBy': 'admin'}, 201),
      );
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(find.text('Transfer tercatat'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Beranda'));
      await tester.pump();
      expect(navigations, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );

  testWidgets('a closed or inaccessible source cannot initiate a transfer', (
    tester,
  ) async {
    var denied = false;
    final api = ReviewApi(
      'fixture',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        if (denied) return jsonResponse({}, 403);
        return request.url.path.endsWith('/availability')
            ? jsonResponse(balance())
            : jsonResponse(lot(closed: true));
      }),
    );
    await mount(tester, api);
    expect(find.textContaining('Kloter ditutup.'), findsOneWidget);
    expect(find.text('Kirim transfer'), findsNothing);
    denied = true;
    await tester.tap(find.byTooltip('Muat ulang saldo'));
    await tester.pumpAndSettle();
    expect(find.text('Data tidak tersedia untuk akun ini.'), findsOneWidget);
    expect(find.text('Kirim transfer'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    api.close();
  });
}
