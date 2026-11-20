import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';
import 'package:sobatnira/main.dart';
import 'package:sobatnira/widgets/adaptive_value.dart';
import '../../support/demo_login.dart';

void main() {
  testWidgets(
    'profit report uses API dates, exact total and five-row pagination',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final receivedAt = DateTime(2026, 11, 19, 12).toUtc().toIso8601String();
      final api = ReviewApi(
        'synthetic-token',
        client: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer synthetic-token');
          if (request.url.path == '/auth/me') {
            return http.Response(
              jsonEncode({
                'access': [
                  {
                    'tenantId': 'tenant',
                    'tenantName': 'Tenant',
                    'factoryId': 'factory',
                    'factoryName': 'Pabrik Uji',
                    'role': 'owner',
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/lots')) {
            return http.Response(jsonEncode({'items': [], 'total': 0}), 200);
          }
          expect(
            request.url.path,
            '/tenants/tenant/factories/factory/production/production-report',
          );
          return http.Response(
            jsonEncode({
              'items': [
                for (var i = 0; i < 7; i++)
                  {
                    'lotId': 'lot-$i',
                    'code': 'K-SAMA',
                    'supplier': 'Pemasok $i',
                    'receivedAt': receivedAt,
                    'batches': [],
                    'calculation': {
                      'productionMarginRupiah': i == 6 ? '-100000' : '100000',
                    },
                  },
              ],
              'totals': {'productionMarginRupiah': '500000', 'lotCount': 7},
              'grades': [],
            }),
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
      await openDemoLogin(tester);
      await tester.enterText(
        find.byType(TextFormField).first,
        'owner@example.invalid',
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        'fixture-password',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Masuk'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Laporan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Margin').first);
      await tester.pumpAndSettle();
      expect(find.text('Rp500.000'), findsOneWidget);
      expect(find.text('Pemasok 0'), findsOneWidget);
      expect(find.text('Pemasok 5'), findsNothing);
      await tester.ensureVisible(find.byTooltip('Berikutnya'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Berikutnya'));
      await tester.pumpAndSettle();
      expect(find.text('Pemasok 6'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is NiraValue && widget.value == '-Rp100.000',
        ),
        findsOneWidget,
      );
      expect(find.text('Rp500.000'), findsOneWidget);
      await tester.ensureVisible(find.text('Pemasok 6'));
      await tester.tap(find.text('Pemasok 6'));
      await tester.pumpAndSettle();
      expect(find.text('19 November 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
