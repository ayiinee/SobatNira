import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';
import 'package:sobatnira/features/pekerjaan/pekerjaan_page.dart';
import 'package:sobatnira/sobatnira_ui.dart';

void main() {
  testWidgets('Pekerjaan loads the API and validates the displayed revision', (
    tester,
  ) async {
    var validated = false;
    var notificationRead = false;
    var listed = 0;
    final task = {
      'id': 'task-demo',
      'document_id': 'document-demo',
      'revision_id': 'revision-demo',
      'version': 2,
      'document_type': 'TRUCK_ARRIVAL_NOTE',
      'sender_name': 'Operator Demo',
      'issue_count': 0,
      'media_asset_id': 'photo-demo',
    };
    final api = ReviewApi(
      'synthetic-token',
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer synthetic-token');
        final endpoint = request.url.path.replaceFirst('/api/v1/mobile/', '');
        if (endpoint == 'review-notifications') {
          return http.Response(
            jsonEncode({'unread_count': notificationRead ? 0 : 1}),
            200,
          );
        }
        if (endpoint == 'review-notifications/task-demo/read') {
          expect(request.method, 'PATCH');
          notificationRead = true;
          return http.Response('{"acknowledged":true}', 200);
        }
        if (endpoint == 'review-tasks') {
          listed++;
          return http.Response(
            jsonEncode({
              'items': validated ? [] : [task],
            }),
            200,
          );
        }
        if (endpoint == 'review-tasks/task-demo/assets/photo-demo') {
          return http.Response('', 404);
        }
        if (endpoint == 'review-tasks/task-demo/intake-lots') {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'lot-demo',
                  'supplierId': 'supplier-demo',
                  'supplierName': 'Pemasok Demo',
                  'displayCode': 'KLOTER-DEMO',
                  'receivedAt': '2026-11-16T01:00:00Z',
                },
              ],
              'next_offset': null,
            }),
            200,
          );
        }
        if (endpoint == 'review-tasks/task-demo') {
          return http.Response(
            jsonEncode({
              ...task,
              'role': 'ADMIN',
              'status': validated ? 'VALIDATED' : 'PENDING_VALIDATION',
              if (validated) 'intake': {'net_weight_kg': '1250'},
              'actions': validated ? [] : ['CORRECT', 'VALIDATE', 'RETURN'],
              'issues': [],
              'extraction': {
                'header': {
                  'net_weight_kg': {
                    'raw_value': '1250',
                    'normalized_value': 1250,
                    'status': 'READ',
                    'source': 'PADDLE_OCR',
                    'unit': 'kg',
                    'evidence': [],
                  },
                },
              },
              'revisions': [
                {
                  'version': 2,
                  'media_asset_id': 'photo-demo',
                  'operator_status': 'CONFIRMED',
                  'processing_status': 'EXTRACTED',
                },
              ],
              'operator_confirmation': {
                'version': 2,
                'confirmed_by': 'Operator Demo',
              },
            }),
            200,
          );
        }
        expect(endpoint, 'documents/document-demo/validate');
        expect(request.method, 'POST');
        expect(request.headers['Idempotency-Key'], isNotEmpty);
        expect(jsonDecode(request.body), {
          'revision_id': 'revision-demo',
          'expected_version': 2,
          'decision': 'VALIDATED',
          'lot_id': 'lot-demo',
          'supplier_id': 'supplier-demo',
        });
        validated = true;
        return http.Response('{"status":"VALIDATED"}', 200);
      }),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: niraTheme(),
        home: Scaffold(body: PekerjaanPage(api: api, active: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Menunggu validasi'), findsOneWidget);
    expect(find.text('1 laporan baru'), findsOneWidget);
    await tester.tap(find.text('Nota Kedatangan Truk'));
    await tester.pumpAndSettle();
    expect(
      find.text('Dikonfirmasi Operator Demo pada revisi 2'),
      findsOneWidget,
    );
    expect(find.textContaining('1250 kg'), findsOneWidget);
    expect(notificationRead, isTrue);
    final validate = find.widgetWithText(FilledButton, 'Validasi revisi ini');
    await tester.ensureVisible(validate);
    await tester.tap(validate);
    await tester.pumpAndSettle();
    expect(find.text('Pilih kloter penerimaan'), findsOneWidget);
    expect(validated, isFalse);
    await tester.tap(find.text('KLOTER-DEMO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sahkan dan catat stok'));
    await tester.pumpAndSettle();
    expect(find.text('Status: VALIDATED'), findsOneWidget);
    expect(find.text('Stok tebu tercatat: 1250 kg'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Belum ada laporan pada status ini.'), findsOneWidget);
    expect(find.text('1 laporan baru'), findsNothing);
    expect(listed, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
