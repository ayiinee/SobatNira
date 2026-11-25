import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';
import 'package:sobatnira/features/pengaturan/production_masters_page.dart';

void main() {
  testWidgets(
    'master writes retain UUID after ambiguous response and persist exact capacity',
    (tester) async {
      final writes = <Json>[];
      final rows = <Json>[];
      final scope = FactoryScope.fromJson({
        'tenantId': 'tenant',
        'factoryId': 'factory',
        'tenantName': 'Tenant',
        'factoryName': 'Factory',
        'role': 'admin',
      });
      final api = ReviewApi(
        'token',
        client: MockClient((request) async {
          expect(
            request.url.path,
            endsWith('/factories/factory/production/masters'),
          );
          if (request.method == 'POST') {
            final body = jsonDecode(request.body) as Json;
            writes.add(body);
            if (writes.length == 1) {
              return http.Response('{}', 503);
            }
            rows.add({...body, 'version': 1, 'createdAt': '2026-11-25'});
            return http.Response(jsonEncode(rows.single), 201);
          }
          return http.Response(jsonEncode({'items': rows, 'usage': []}), 200);
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: ProductionMastersPage(api: api, scope: scope, kind: 'wok'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tambah master'));
      await tester.pumpAndSettle();
      for (final (index, value) in [
        '1',
        'Wajan satu',
        '115.25',
        'Ukur kapasitas sintetis',
      ].indexed) {
        await tester.enterText(find.byType(TextField).at(index), value);
      }
      await tester.tap(find.text('Simpan versi baru'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Periksa ulang permintaan yang sama'));
      await tester.pumpAndSettle();
      expect(writes.length, 2);
      expect(writes[0], writes[1]);
      expect(writes.last['capacityLiters'], '115.25');
      expect(writes.last['version'], 0);
      expect(find.textContaining('115.25 L'), findsOneWidget);
      expect(find.text('1 · Wajan satu'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
