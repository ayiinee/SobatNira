import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:sobatnira/features/kloter/sugar_stock_page.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';

const _base = String.fromEnvironment('PRODUCTION_TEST_API');
const _tenant = String.fromEnvironment('PRODUCTION_TEST_TENANT');
const _factory = String.fromEnvironment('PRODUCTION_TEST_FACTORY');
const _lot = String.fromEnvironment('PRODUCTION_TEST_TRANSFER_LOT');

class _RealHttp extends HttpOverrides {}

void main() {
  testWidgets(
    'Flutter records physical stock, production and rework through NestJS and PostgreSQL',
    (tester) async {
      expect(Uri.parse(_base).host, '127.0.0.1');
      final api = ReviewApi(
        'fixture-admin',
        baseUrl: _base,
        client: IOClient(
          HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp()),
        ),
      );
      addTearDown(api.close);
      final scope = FactoryScope.fromJson({
        'tenantId': _tenant,
        'factoryId': _factory,
        'factoryName': 'Pabrik sintetis',
        'tenantName': 'Tenant sintetis',
        'role': 'admin',
      });
      final root = [...scope.basePath, 'production'];
      Future<T> backend<T>(Future<T> Function() work) async {
        T? result;
        Object? failure;
        var complete = false;
        work().then(
          (value) {
            result = value;
            complete = true;
          },
          onError: (Object error) {
            failure = error;
            complete = true;
          },
        );
        for (var n = 0; !complete && n < 200; n++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 30));
        }
        if (failure != null) {
          throw failure!;
        }
        expect(complete, isTrue, reason: 'API sintetis tidak merespons.');
        return result as T;
      }

      Future<Json> command(List<String> path, Json body) =>
          backend(() => api.writeProduction(path, body));
      await command(
        [...root, 'masters'],
        {
          'requestId': ReviewApi.requestUuid(),
          'kind': 'grade',
          'code': 'A',
          'version': 0,
          'name': 'Grade A',
          'active': true,
          'reason': 'Fixture sintetis',
        },
      );
      await command(
        [...root, 'masters'],
        {
          'requestId': ReviewApi.requestUuid(),
          'kind': 'wok',
          'code': '1',
          'version': 0,
          'name': 'Wajan 1',
          'capacityLiters': '100',
          'active': true,
          'reason': 'Fixture sintetis',
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SugarStockPage(api: api, scope: scope),
        ),
      );
      Future<void> waitFor(String text) async {
        for (var n = 0; n < 100; n++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 30));
          if (find.text(text).evaluate().isNotEmpty) {
            return;
          }
        }
        fail('Teks tidak muncul: $text');
      }

      await waitFor('Catat saldo awal');
      await tester.tap(find.text('Catat saldo awal'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'A');
      await tester.enterText(find.byType(TextField).at(1), '2');
      await tester.enterText(
        find.byType(TextField).at(2),
        'Hitung fisik sintetis Flutter',
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Catat saldo awal').last,
      );
      await tester.pump();
      await waitFor('Sesuaikan stok');
      var stock = await backend(() => api.sugarStock(scope));
      expect((stock['sources'] as List).single['onHandKg'], '2');
      final source = (stock['sources'] as List).single['id'];
      await command(
        [...root, 'sugar', 'rework-enablement'],
        {
          'requestId': ReviewApi.requestUuid(),
          'version': stock['version'],
          'reason': 'Kontrak laporan diuji sintetis',
          'reportHandlingConfirmed': true,
        },
      );
      await backend(
        () => api.saveLotCosts(scope, _lot, {
          'caneCostRupiah': '100',
          'operationalCostRupiah': '100',
          'ingredientCostRupiah': '0',
          'otherCostRupiah': '0',
        }),
      );
      final batch = ReviewApi.requestUuid();
      await backend(
        () => api.createBatch(scope, {
          'id': batch,
          'kind': 'rework',
          'lotId': _lot,
          'code': 'FLUTTER-REWORK',
          'wokNumber': 1,
          'occurredAt': '2026-11-16T03:00:00Z',
          'quantityMl': '10000',
          'physicalWeightKg': '3',
          'grades': [
            {'code': 'A', 'weightKg': '3', 'pricePerKgRupiah': '100'},
          ],
        }),
      );
      await backend(() => api.reserveBatchJuice(scope, _lot, batch, '10000'));
      stock = await backend(() => api.sugarStock(scope));
      await command(
        [...root, 'batches', batch, 'rework-inputs'],
        {
          'requestId': ReviewApi.requestUuid(),
          'version': stock['version'],
          'reason': 'Gula saldo awal dipakai ulang',
          'sourceId': source,
          'weightKg': '2',
        },
      );
      await backend(() => api.finishBatch(scope, batch));
      await backend(() => api.finishBatch(scope, batch));
      stock = await backend(() => api.sugarStock(scope));
      expect(
        (stock['sources'] as List).firstWhere(
          (s) => s['id'] == source,
        )['onHandKg'],
        '0',
      );
      expect(
        (stock['sources'] as List).firstWhere(
          (s) => s['batchId'] == batch,
        )['onHandKg'],
        '3',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: BatchTracePage(api: api, scope: scope, batchId: batch),
        ),
      );
      await waitFor('Hasil fisik bruto: 3 kg');
      expect(find.text('Gula lama terpakai: 2 kg'), findsOneWidget);
      expect(find.text('Tambahan bersih: 1 kg'), findsOneWidget);
      await expectLater(
        backend(() => api.productionReport(scope)),
        throwsA(isA<ReviewApiError>().having((e) => e.status, 'status', 409)),
      );
      api.close();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    skip: _base.isEmpty || _lot.isEmpty,
  );
}
