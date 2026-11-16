import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';
import 'package:sobatnira/main.dart';

import '../../support/demo_login.dart';

void main() {
  testWidgets('Pekerjaan loads the API and validates the displayed revision', (
    tester,
  ) async {
    var validated = false;
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
        if (endpoint == 'review-tasks/task-demo') {
          return http.Response(
            jsonEncode({
              ...task,
              'status': validated ? 'VALIDATED' : 'PENDING_VALIDATION',
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
        });
        validated = true;
        return http.Response('{"status":"VALIDATED"}', 200);
      }),
    );
    addTearDown(api.close);

    await tester.pumpWidget(SobatNiraApp(reviewApi: api));
    await tester.pumpAndSettle();
    await openDemoLogin(tester);
    await submitDemoLogin(tester);
    final semantics = tester.ensureSemantics();
    try {
      await tester.tap(find.bySemanticsLabel('Pekerjaan'));
    } finally {
      semantics.dispose();
    }
    await tester.pumpAndSettle();
    expect(find.text('Menunggu validasi'), findsOneWidget);
    await tester.tap(find.text('Nota Kedatangan Truk'));
    await tester.pumpAndSettle();
    expect(
      find.text('Dikonfirmasi Operator Demo pada revisi 2'),
      findsOneWidget,
    );
    expect(find.textContaining('1250 kg'), findsOneWidget);
    final validate = find.widgetWithText(FilledButton, 'Validasi revisi ini');
    await tester.ensureVisible(validate);
    await tester.tap(validate);
    await tester.pumpAndSettle();
    expect(find.text('Status: VALIDATED'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Belum ada laporan pada status ini.'), findsOneWidget);
    expect(listed, 2);
  });
}
