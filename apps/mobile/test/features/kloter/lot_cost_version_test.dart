import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/features/kloter/official_batch_workflow.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';

void main() {
  testWidgets('cost conflict keeps draft and requires a fresh version', (
    tester,
  ) async {
    var version = 1;
    final writes = <Json>[];
    final api = ReviewApi(
      'fixture',
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'version': version,
              'cane_rupiah': version == 1 ? '100' : '200',
              'operational_rupiah': '0',
              'ingredient_rupiah': '0',
              'other_rupiah': '0',
            }),
            200,
          );
        }
        writes.add(jsonDecode(request.body) as Json);
        if (writes.last['version'] != version) {
          return http.Response(
            jsonEncode({
              'code': 'LOT_COST_VERSION_CONFLICT',
              'message': 'Biaya sudah berubah.',
            }),
            409,
          );
        }
        return http.Response('{}', 200);
      }),
    );
    addTearDown(api.close);
    final scope = FactoryScope.fromJson({
      'tenantId': 'tenant',
      'tenantName': 'Fixture',
      'factoryId': 'factory',
      'factoryName': 'Fixture',
      'role': 'admin',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showLotCostsForm(context, api, scope, 'lot', 'LOT'),
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    final cane = find.byType(TextFormField).first;
    await tester.enterText(cane, '150');
    version = 2;
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(writes.single['version'], 1);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Simpan'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Muat biaya terbaru'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Biaya tebu (Rp): 200'), findsOneWidget);
    expect(find.text('150'), findsOneWidget);
    expect(writes, hasLength(1));
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(writes.last['version'], 2);
    expect(writes.last['caneCostRupiah'], '150');
  });
}
