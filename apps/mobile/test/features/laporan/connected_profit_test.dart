import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';
import 'package:sobatnira/features/laporan/connected_profit_page.dart';
import 'package:sobatnira/sobatnira_ui.dart';

void main() {
  testWidgets(
    'profit report uses API dates, exact total and five-row pagination',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = ReviewApi(
        'synthetic-token',
        client: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer synthetic-token');
          expect(request.url.path, contains('/production/profit-report'));
          return http.Response(
            jsonEncode({
              'items': [
                for (var i = 0; i < 7; i++)
                  {
                    'lotId': 'lot-$i',
                    'code': 'K-SAMA',
                    'supplier': 'Pemasok $i',
                    'receivedAt': '2026-11-19T01:00:00Z',
                    'calculation': {
                      'productionMarginRupiah': i == 6 ? '-100000' : '100000',
                    },
                  },
              ],
              'totalMarginRupiah': '500000',
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      final scope = FactoryScope.fromJson({
        'tenantId': 'tenant',
        'tenantName': 'Tenant',
        'factoryId': 'factory',
        'factoryName': 'Pabrik Uji',
        'role': 'owner',
        'userId': 'user',
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: niraTheme(),
          home: ConnectedProfitPage(api: api, scope: scope),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rp500.000'), findsOneWidget);
      expect(find.text('Data disahkan · 7 kloter'), findsOneWidget);
      expect(find.text('Pemasok 0'), findsOneWidget);
      expect(find.text('Pemasok 5'), findsNothing);
      expect(find.text('19 November 2026'), findsNWidgets(5));
      await tester.ensureVisible(find.text('Berikutnya'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Berikutnya'));
      await tester.pumpAndSettle();
      expect(find.text('Pemasok 6'), findsOneWidget);
      expect(find.text('-Rp100.000'), findsOneWidget);
      expect(find.text('Rp500.000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
