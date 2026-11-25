import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/features/kloter/batch_juice_reservation_page.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';

void main() {
  testWidgets('reserves donor and own juice with separate requests', (tester) async {
    final reservations = <Json>[];
    final api = ReviewApi('fixture', client: MockClient((request) async {
      final path = request.url.path;
      Object data;
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Json;
        reservations.add({...body, 'state': 'reserved', 'lotCode': body['originLotId']});
        data = body;
      } else if (path.endsWith('/batches/batch')) {
        data = {'status': 'draft', 'remainingMl': '${100000 - reservations.fold<int>(0, (n, r) => n + int.parse(r['quantityMl'] as String))}',
          'reservations': reservations, 'is_synthetic': false};
      } else if (path.endsWith('/availability')) {
        data = {'origins': [for (final id in ['A', 'B']) {'originLotId': id, 'availableMl': id == 'A' ? '80000' : '20000'}]};
      } else {
        data = {'displayCode': request.url.pathSegments.last};
      }
      return http.Response(jsonEncode(data), request.method == 'POST' ? 201 : 200);
    }));
    addTearDown(api.close);
    final scope = FactoryScope.fromJson({'tenantId':'t','tenantName':'T','factoryId':'f','factoryName':'F','role':'admin'});
    await tester.pumpWidget(MaterialApp(home: BatchJuiceReservationPage(api: api, scope: scope, lotId: 'B', batchId: 'batch')));
    await tester.pumpAndSettle();
    for (final (label, liters) in [('A · 80 L', '80'), ('B · 20 L', '20')]) {
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), liters);
      await tester.tap(find.text('Tambah reservasi'));
      await tester.pumpAndSettle();
    }
    expect(reservations.map((r) => r['originLotId']), ['A', 'B']);
    expect(reservations.map((r) => r['requestId']).toSet().length, 2);
    expect(find.text('Sisa kebutuhan: 0 L'), findsOneWidget);
  });
}
