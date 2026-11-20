import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/features/beranda/home_page.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';
import 'package:sobatnira/main.dart';
import '../../support/demo_login.dart';

void main() {
  testWidgets(
    'app login opens the shared home and keeps factory scope in review',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final requests = <Uri>[];
      final api = ReviewApi(
        'fixture',
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer fixture');
          requests.add(request.url);
          final path = request.url.path;
          final Object result;
          if (path == '/auth/me') {
            result = {
              'access': [
                for (final factory in ['A', 'B'])
                  {
                    'tenantId': 'tenant',
                    'tenantName': 'Tenant',
                    'factoryId': factory,
                    'factoryName': 'Pabrik $factory',
                    'role': 'admin',
                  },
              ],
            };
          } else if (path.endsWith('/production-report')) {
            result = {
              'synthetic': false,
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
            };
          } else if (path.endsWith('/lots')) {
            result = {'items': [], 'total': 0};
          } else if (path == '/api/v1/mobile/review-tasks') {
            result = {'items': []};
          } else if (path == '/api/v1/mobile/review-notifications') {
            result = {'unread_count': 0};
          } else {
            throw StateError('Unexpected route $path');
          }
          return http.Response(jsonEncode(result), 200);
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
        find.byType(TextFormField).at(0),
        'admin@example.invalid',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'fixture-password',
      );
      final submit = find.widgetWithText(FilledButton, 'Masuk');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.byType(NiraHome), findsOneWidget);
      expect(find.text('Pabrik A'), findsOneWidget);
      await tester.tap(find.byTooltip('Pilih pabrik'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pabrik B'));
      await tester.pumpAndSettle();
      expect(
        requests.any((uri) => uri.path.contains('/factories/B/lots')),
        isTrue,
      );
      await tester.tap(find.bySemanticsLabel('Pengaturan'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Pekerjaan'));
      await tester.tap(find.text('Pekerjaan'));
      await tester.pumpAndSettle();
      final review = requests.where(
        (uri) => uri.path.startsWith('/api/v1/mobile/'),
      );
      expect(review, isNotEmpty);
      expect(
        review.every((uri) => uri.queryParameters['factory_id'] == 'B'),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
