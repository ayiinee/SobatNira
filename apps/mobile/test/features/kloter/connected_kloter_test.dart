import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/main.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';

void main() {
  testWidgets(
    'uses the selected factory and shares its authenticated review session',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(418, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const lot = {
        'id': 'lot-b',
        'displayCode': 'OCR-B',
        'supplierName': 'Pemasok B',
        'receivedAt': '2026-11-16T01:00:00Z',
      };
      final requests = <Uri>[];
      final api = ReviewApi(
        'fixture',
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer fixture');
          requests.add(request.url);
          final result = switch (request.url.path) {
            '/auth/me' => {
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
            },
            '/tenants/tenant/factories/A/lots' => {
              'items': [],
              'limit': 20,
              'total': 0,
            },
            '/tenants/tenant/factories/B/lots' => {
              'items': [lot],
              'limit': 20,
              'total': 1,
            },
            '/tenants/tenant/factories/B/lots/lot-b' => {
              ...lot,
              'status': 'open',
              'netWeightGrams': '1250010',
              'milling': {
                'document': {'documentId': 'nota-b', 'revisionId': 'revisi-b'},
              },
            },
            '/tenants/tenant/factories/B/lots/lot-b/juice/availability' => {
              'onHandMl': '90000.25',
              'reservedMl': '10000',
              'availableMl': '80000.25',
              'origins': [
                {'originLotId': 'lot-b', 'availableMl': '80000.25'},
              ],
            },
            '/tenants/tenant/factories/B/lots/lot-b/closure' => {
              'status': 'open',
              'closureId': null,
            },
            '/tenants/tenant/factories/B/lots/lot-b/closure/history' => {
              'items': [],
              'total': 0,
              'offset': 0,
              'limit': 20,
            },
            '/tenants/tenant/factories/A/production/production-report' ||
            '/tenants/tenant/factories/B/production/production-report' => {
              'items': [],
              'totals': {},
              'grades': [],
            },
            '/tenants/tenant/factories/B/production/batches' => {
              'items': [],
              'total': 0,
            },
            '/api/v1/mobile/review-tasks' => {'items': []},
            '/api/v1/mobile/review-notifications' => {'unread_count': 1},
            _ => throw StateError('Unexpected route ${request.url.path}'),
          };
          return http.Response(jsonEncode(result), 200);
        }),
      );

      await tester.pumpWidget(
        SobatNiraApp(
          configurationErrors: const [],
          signIn: (email, password) async {
            expect(email, 'admin@example.invalid');
            expect(password, 'fixture-password');
            return api;
          },
        ),
      );
      expect(requests, isEmpty);
      await tester.tap(find.text('Masuk'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'admin@example.invalid',
      );
      await tester.enterText(find.byType(TextField).last, 'fixture-password');
      await tester.tap(find.text('Masuk'));
      await tester.pumpAndSettle();
      expect(
        requests.any((uri) => uri.path.endsWith('/factories/A/lots')),
        isTrue,
      );
      await tester.tap(find.byTooltip('Pilih pabrik'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pabrik B'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Kloter'));
      await tester.pumpAndSettle();

      final sent = requests.length;
      await tester.enterText(find.byType(TextField), 'A & B');
      await tester.pumpAndSettle();
      expect(find.text('OCR-B'), findsNothing);
      await tester.enterText(find.byType(TextField), 'OCR');
      await tester.pumpAndSettle();
      expect(requests, hasLength(sent));
      await tester.tap(find.text('OCR-B'));
      await tester.pumpAndSettle();
      expect(find.text('1.250,01 kg'), findsOneWidget);

      await tester.tap(find.text('Data tebu dan penggilingan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Penggilingan'));
      await tester.pumpAndSettle();
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('revisi-b'),
        150,
        scrollable: scrollable,
      );
      expect(find.text('revisi-b'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Penutupan dan riwayat'),
        150,
        scrollable: scrollable,
      );
      expect(find.text('80,00025 L'), findsOneWidget);
      await tester.tap(find.text('Penutupan dan riwayat'));
      await tester.pumpAndSettle();
      expect(find.text('Tutup kloter'), findsOneWidget);
      expect(
        requests
            .where((uri) => uri.path.endsWith('/closure/history'))
            .single
            .path,
        '/tenants/tenant/factories/B/lots/lot-b/closure/history',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transfer nira'));
      await tester.pumpAndSettle();
      expect(find.text('Kirim transfer'), findsOneWidget);
      expect(find.text('80.00025 L'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Buka Pekerjaan'));
      await tester.pumpAndSettle();
      final review = requests
          .where((uri) => uri.path.startsWith('/api/v1/mobile/'))
          .toList();
      expect(
        review.map((uri) => uri.path),
        contains('/api/v1/mobile/review-tasks'),
      );
      expect(
        review.every((uri) => uri.queryParameters['factory_id'] == 'B'),
        isTrue,
      );
      expect(
        requests
            .where((uri) => uri.path.endsWith('/juice/availability'))
            .length,
        greaterThan(1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
