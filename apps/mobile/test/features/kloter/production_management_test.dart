import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/features/kloter/production_catalog_page.dart';
import 'package:sobatnira/features/kloter/production_lot_editor.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';
import 'package:sobatnira/main.dart';

final scope = FactoryScope.fromJson({
  'tenantId': 'tenant',
  'tenantName': 'Tenant',
  'factoryId': 'factory',
  'factoryName': 'Pabrik Uji',
});

Future<void> press(
  WidgetTester tester,
  String label, {
  bool tooltip = false,
}) async {
  final button = (tooltip ? find.byTooltip(label) : find.text(label)).last;
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String label, String value) async {
  await tester.enterText(find.widgetWithText(TextFormField, label), value);
}

void main() {
  testWidgets(
    'catalogue uses scoped POST and PATCH, retains errors and filters pages',
    (tester) async {
      final writes = <Json>[];
      var saved = false;
      var active = true;
      var duplicate = true;
      final requests = <http.Request>[];
      final api = ReviewApi(
        'fixture',
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer fixture');
          expect(
            request.url.path,
            startsWith('/tenants/tenant/factories/factory/cane-types'),
          );
          requests.add(request);
          final values = request.body.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(request.body) as Json;
          if (request.method == 'POST') {
            writes.add(values);
            if (duplicate) return http.Response('{}', 409);
            saved = true;
            return http.Response(jsonEncode({'id': 'type'}), 201);
          }
          if (request.method == 'PATCH') {
            writes.add(values);
            active = values['isActive'] as bool;
            return http.Response(jsonEncode({'id': 'type'}), 200);
          }
          final offset = int.parse(request.url.queryParameters['offset']!);
          final isActive = request.url.queryParameters['isActive'];
          return http.Response(
            jsonEncode({
              'items':
                  saved &&
                      offset == 0 &&
                      (isActive == null || isActive == '$active')
                  ? [
                      {
                        'id': 'type',
                        'name': 'Jenis Uji',
                        'code': 'DEMO',
                        'isActive': active,
                      },
                    ]
                  : [],
              'total': saved ? 21 : 0,
              'limit': 20,
              'offset': offset,
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ProductionCatalogPage(
            api: api,
            scope: scope,
            kind: ProductionCatalog.caneTypes,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await press(tester, 'Tambah jenis tebu');
      await enter(tester, 'Kode jenis tebu', 'DEMO');
      await enter(tester, 'Nama', 'Jenis Uji');
      await press(tester, 'Simpan');
      expect(
        find.text('Kode jenis tebu sudah terdaftar. Gunakan kode lain.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextFormField, 'Jenis Uji'), findsOneWidget);
      duplicate = false;
      await press(tester, 'Simpan');
      expect(writes.last, {'name': 'Jenis Uji', 'code': 'DEMO'});
      await press(tester, 'Jenis Uji');
      expect(
        find.widgetWithText(TextFormField, 'Kode jenis tebu'),
        findsNothing,
      );
      await tester.tap(find.byType(SwitchListTile));
      await press(tester, 'Simpan');
      expect(writes.last, {'name': 'Jenis Uji', 'isActive': false});
      expect(
        requests.where((r) => r.method == 'PATCH').single.url.path,
        endsWith('/cane-types/type'),
      );
      expect(find.text('DEMO · Nonaktif'), findsOneWidget);
      await press(tester, 'Berikutnya', tooltip: true);
      expect(requests.last.url.queryParameters['offset'], '20');
      await tester.enterText(find.byType(TextField), 'DEMO & B');
      await tester.tap(find.byTooltip('Cari'));
      await tester.pumpAndSettle();
      expect(requests.last.url.queryParameters, containsPair('offset', '0'));
      expect(requests.last.url.queryParameters, containsPair('q', 'DEMO & B'));
      await press(tester, 'Semua status');
      await press(tester, 'Aktif');
      expect(requests.last.url.queryParameters['isActive'], 'true');
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );

  testWidgets(
    'lot editor uses active supplier pagination and protects approved fields',
    (tester) async {
      final writes = <http.Request>[];
      final api = ReviewApi(
        'fixture',
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer fixture');
          expect(
            request.url.path,
            startsWith('/tenants/tenant/factories/factory/'),
          );
          if (request.method != 'GET') {
            writes.add(request);
            return http.Response('{}', request.method == 'POST' ? 201 : 200);
          }
          expect(request.url.path, endsWith('/suppliers'));
          expect(request.url.queryParameters['isActive'], 'true');
          final next = request.url.queryParameters['offset'] == '20';
          return http.Response(
            jsonEncode({
              'items': next
                  ? [
                      {
                        'id': 'supplier',
                        'name': 'Pemasok Aktif',
                        'isActive': true,
                      },
                    ]
                  : [],
              'total': 21,
              'limit': 20,
              'offset': next ? 20 : 0,
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => ProductionLotEditor(api: api, scope: scope),
                ),
              ),
              child: const Text('Buka form'),
            ),
          ),
        ),
      );
      await press(tester, 'Buka form');
      await press(tester, 'Simpan kloter');
      expect(writes, isEmpty);
      expect(find.text('Pilih pemasok aktif.'), findsWidgets);
      await tester.enterText(find.byType(TextField), 'UJI-LOT');
      await press(tester, 'Pemasok');
      await press(tester, 'Berikutnya', tooltip: true);
      await press(tester, 'Pemasok Aktif');
      await press(tester, 'Simpan kloter');
      final created = jsonDecode(writes.single.body) as Json;
      expect(created['displayCode'], 'UJI-LOT');
      expect(created['supplierId'], 'supplier');
      expect(created['receivedAt'], endsWith('Z'));
      expect(created['receivedAt'], matches(RegExp(r'\.\d{3}Z$')));
      expect(DateTime.parse(created['receivedAt'] as String).isUtc, isTrue);
      final lot = {
        ...created,
        'id': 'lot',
        'supplierName': 'Pemasok Nonaktif',
        'intake': {'id': 'receipt'},
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ProductionLotEditor(api: api, scope: scope, lot: lot),
                ),
              ),
              child: const Text('Edit resmi'),
            ),
          ),
        ),
      );
      await press(tester, 'Edit resmi');
      final supplierTile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Pemasok'),
      );
      final timeTile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Waktu penerimaan'),
      );
      expect(supplierTile.onTap, isNull);
      expect(timeTile.onTap, isNull);
      await tester.enterText(find.byType(TextField), '');
      await press(tester, 'Simpan kloter');
      expect(writes.last.method, 'PATCH');
      expect(writes.last.url.path, endsWith('/lots/lot'));
      expect(jsonDecode(writes.last.body), {'displayCode': null});
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );

  testWidgets(
    'unapproved lot preserves its timestamp and reports a concurrent approval',
    (tester) async {
      Json? sent;
      final api = ReviewApi(
        'fixture',
        client: MockClient((request) async {
          expect(request.method, 'PATCH');
          sent = jsonDecode(request.body) as Json;
          return http.Response('{}', 409);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ProductionLotEditor(
            api: api,
            scope: scope,
            lot: {
              'id': 'lot',
              'displayCode': 'BEFORE',
              'supplierId': 'old',
              'supplierName': 'Pemasok Lama',
              'receivedAt': '2026-11-16T01:23:45.123Z',
              'intake': null,
            },
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'AFTER');
      await press(tester, 'Simpan kloter');
      expect(sent, {'displayCode': 'AFTER'});
      expect(
        find.textContaining('Penerimaan kloter sudah disahkan.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, 'AFTER'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );

  testWidgets('unapproved lot can change supplier and local receipt time', (
    tester,
  ) async {
    Json? sent;
    final original = DateTime.parse('2026-11-16T01:23:45.123Z').toLocal();
    final api = ReviewApi(
      'fixture',
      client: MockClient((request) async {
        if (request.method == 'GET') {
          expect(request.url.queryParameters['isActive'], 'true');
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'new-supplier',
                  'name': 'Pemasok Pengganti',
                  'isActive': true,
                },
              ],
              'total': 1,
              'limit': 20,
              'offset': 0,
            }),
            200,
          );
        }
        sent = jsonDecode(request.body) as Json;
        return http.Response('{}', 200);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => ProductionLotEditor(
                  api: api,
                  scope: scope,
                  lot: {
                    'id': 'lot',
                    'displayCode': null,
                    'supplierId': 'old',
                    'supplierName': 'Pemasok Lama',
                    'receivedAt': '2026-11-16T01:23:45.123Z',
                    'intake': null,
                  },
                ),
              ),
            ),
            child: const Text('Edit'),
          ),
        ),
      ),
    );
    await press(tester, 'Edit');
    await press(tester, 'Pemasok');
    await press(tester, 'Pemasok Pengganti');
    await press(tester, 'Waktu penerimaan');
    await press(tester, '${original.day + 1}');
    await press(tester, 'OK');
    await press(tester, 'OK');
    await press(tester, 'Simpan kloter');
    expect(sent, {
      'supplierId': 'new-supplier',
      'receivedAt': DateTime(
        original.year,
        original.month,
        original.day + 1,
        original.hour,
        original.minute,
      ).toUtc().toIso8601String(),
    });
    await tester.pumpWidget(const SizedBox.shrink());
    api.close();
  });

  testWidgets(
    'connected home opens master data with the same factory and reloads lots',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final paths = <String>[];
      final api = ReviewApi(
        'fixture',
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/auth/me') {
            return http.Response(
              jsonEncode({
                'access': [
                  {
                    'tenantId': 'tenant',
                    'tenantName': 'Tenant',
                    'factoryId': 'factory',
                    'factoryName': 'Pabrik Uji',
                    'role': 'admin',
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/production-report')) {
            return http.Response(
              jsonEncode({
                'items': [],
                'grades': [],
                'totals': {
                  'lotCount': 0,
                  'producedLotCount': 0,
                  'batchCount': 0,
                  'caneNetKg': '0',
                  'finalSugarKg': '0',
                  'productionValueRupiah': '0',
                  'totalCostRupiah': '0',
                  'productionMarginRupiah': '0',
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({'items': [], 'total': 0, 'offset': 0, 'limit': 20}),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        SobatNiraApp(
          configurationErrors: const [],
          signIn: (_, _) async => api,
        ),
      );
      await press(tester, 'Masuk');
      await tester.enterText(
        find.byType(TextField).first,
        'fixture@example.invalid',
      );
      await tester.enterText(find.byType(TextField).last, 'fixture');
      await press(tester, 'Masuk');
      await tester.tap(find.bySemanticsLabel('Pengaturan'));
      await tester.pumpAndSettle();
      for (final label in ['Pemasok', 'Jenis tebu']) {
        final row = find.bySemanticsLabel(label).hitTestable();
        await tester.scrollUntilVisible(row, 200);
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(
          paths.last,
          endsWith(label == 'Pemasok' ? '/suppliers' : '/cane-types'),
        );
        await tester.tap(find.byTooltip('Kembali'));
        await tester.pumpAndSettle();
        expect(paths.last, '/tenants/tenant/factories/factory/lots');
      }
      await tester.tap(find.bySemanticsLabel('Kloter'));
      await tester.pumpAndSettle();
      await press(tester, 'Tambah kloter', tooltip: true);
      expect(find.byType(ProductionLotEditor), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
