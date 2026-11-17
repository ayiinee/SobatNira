import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:sobatnira/features/kloter/production_catalog_page.dart';
import 'package:sobatnira/features/kloter/production_lot_editor.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';

const _base = String.fromEnvironment('PRODUCTION_TEST_API');
const _tenant = String.fromEnvironment('PRODUCTION_TEST_TENANT');
const _factory = String.fromEnvironment('PRODUCTION_TEST_FACTORY');

class _LocalHttpOverrides extends HttpOverrides {}

// Run only against the synthetic, rollback-only NestJS fixture.
void main() {
  testWidgets('production forms persist through NestJS into PostgreSQL', (
    tester,
  ) async {
    expect(Uri.parse(_base).host, '127.0.0.1');
    final client = IOClient(
      HttpOverrides.runWithHttpOverrides(HttpClient.new, _LocalHttpOverrides()),
    );
    final api = ReviewApi('fixture-admin', baseUrl: _base, client: client);
    final scope = FactoryScope.fromJson({
      'tenantId': _tenant,
      'tenantName': 'Tenant sintetis',
      'factoryId': _factory,
      'factoryName': 'Pabrik sintetis',
    });
    addTearDown(api.close);
    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    final supplierName = 'Pemasok UI $suffix';
    final caneCode = 'UI-$suffix';
    final lotCode = 'KLOTER-UI-$suffix';

    Future<T> backend<T>(Future<T> Function() request) async {
      T? result;
      Object? failure;
      var complete = false;
      request().then(
        (value) {
          result = value;
          complete = true;
        },
        onError: (Object error) {
          failure = error;
          complete = true;
        },
      );
      for (var attempt = 0; !complete && attempt < 200; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      if (failure != null) throw failure!;
      expect(complete, isTrue, reason: 'The synthetic API did not respond.');
      return result as T;
    }

    Future<void> waitFor(Finder finder) async {
      for (var attempt = 0; attempt < 200; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 20));
        if (finder.evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty) {
          await tester.pumpAndSettle();
          return;
        }
      }
      fail(
        'UI did not finish loading $finder. Visible text ${tester.widgetList<Text>(find.byType(Text)).map((widget) => widget.data).toList()}',
      );
    }

    Future<void> press(String text) async {
      final finder = find.text(text).last;
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> showCatalog(ProductionCatalog kind) async {
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: ProductionCatalogPage(api: api, scope: scope, kind: kind),
        ),
      );
      await waitFor(find.text('Tambah ${kind.label.toLowerCase()}'));
    }

    await showCatalog(ProductionCatalog.suppliers);
    await press('Tambah pemasok');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nama'),
      supplierName,
    );
    await press('Simpan');
    await waitFor(find.widgetWithText(ListTile, supplierName));
    await press(supplierName);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nama'),
      '$supplierName Baru',
    );
    await tester.tap(find.byType(SwitchListTile));
    await press('Simpan');
    await waitFor(find.widgetWithText(ListTile, '$supplierName Baru'));
    var rows = await backend(
      () => api.catalog(scope, ProductionCatalog.suppliers, search: suffix),
    );
    expect(rows['items'], hasLength(1));
    final supplier = (rows['items'] as List).single as Json;
    expect(supplier['isActive'], false);
    await press('$supplierName Baru');
    await tester.tap(find.byType(SwitchListTile));
    await press('Simpan');
    await waitFor(find.widgetWithText(ListTile, '$supplierName Baru'));

    await showCatalog(ProductionCatalog.caneTypes);
    await press('Tambah jenis tebu');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Kode jenis tebu'),
      caneCode,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nama'),
      'Jenis UI $suffix',
    );
    await press('Simpan');
    await waitFor(find.widgetWithText(ListTile, 'Jenis UI $suffix'));
    await press('Jenis UI $suffix');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nama'),
      'Jenis UI Baru $suffix',
    );
    await tester.tap(find.byType(SwitchListTile));
    await press('Simpan');
    await waitFor(find.widgetWithText(ListTile, 'Jenis UI Baru $suffix'));
    rows = await backend(
      () => api.catalog(scope, ProductionCatalog.caneTypes, search: suffix),
    );
    final cane = (rows['items'] as List).single as Json;
    expect(cane['code'], caneCode);
    expect(cane['isActive'], false);

    Future<void> showLotEditor([Json? lot]) async {
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ProductionLotEditor(api: api, scope: scope, lot: lot),
                ),
              ),
              child: const Text('Buka'),
            ),
          ),
        ),
      );
      await press('Buka');
    }

    await showLotEditor();
    await tester.enterText(find.byType(TextField), lotCode);
    await press('Pemasok');
    await waitFor(find.widgetWithText(ListTile, '$supplierName Baru'));
    await press('$supplierName Baru');
    await press('Simpan kloter');
    await waitFor(find.text('Buka'));
    final lots = await backend(
      () => api.lots(scope, offset: 0, search: lotCode),
    );
    final created = (lots['items'] as List).single as Json;
    expect(created['supplierId'], supplier['id']);
    expect(created['receivedAt'], endsWith('Z'));
    final detail = await backend(() => api.lot(scope, created['id'] as String));
    expect(detail['intake'], isNull);
    await showLotEditor(detail);
    await tester.enterText(find.byType(TextField), '');
    await press('Simpan kloter');
    await waitFor(find.text('Buka'));
    final edited = await backend(() => api.lot(scope, created['id'] as String));
    expect(edited['displayCode'], isNull);
    expect(edited['supplierId'], created['supplierId']);
    expect(
      DateTime.parse(edited['receivedAt'] as String),
      DateTime.parse(created['receivedAt'] as String),
    );

    final history = await backend(
      () => client.get(
        Uri.parse(
          '$_base/tenants/$_tenant/factories/$_factory/lots/${created['id']}/history',
        ),
        headers: {'Authorization': 'Bearer fixture-admin'},
      ),
    );
    expect(history.statusCode, 200);
    expect((jsonDecode(history.body) as Json)['total'], 2);
    await tester.pumpWidget(const SizedBox.shrink());
    api.close();
    await tester.pump();
  }, skip: _base.isEmpty);
}
