import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';
import 'package:sobatnira/features/pekerjaan/review_detail_page.dart';

void main() {
  final image = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAACXBIWXMAAAPoAAAD6AG1e1JrAAAADklEQVQImWP4DwYMEAoAU7oL9W/sIDEAAAAASUVORK5CYII=',
  );
  for (final previewFails in [false, true]) {
    testWidgets(
      'photo uses preview then requests original on demand, preview failure=$previewFails',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final photos = <Uri>[];
        final api = ReviewApi(
          'synthetic',
          client: MockClient((request) async {
            expect(request.headers['Authorization'], 'Bearer synthetic');
            if (request.url.path.contains('/assets/')) {
              photos.add(request.url);
              if (previewFails &&
                  request.url.queryParameters['variant'] == 'preview') {
                return http.Response('', 503);
              }
              return http.Response.bytes(image, 200);
            }
            if (request.method == 'PATCH') return http.Response('{}', 200);
            return http.Response(
              jsonEncode({
                'media_asset_id': 'asset',
                'document_type': 'TRUCK_ARRIVAL_NOTE',
                'document_id': 'document',
                'revision_id': 'revision',
                'version': 1,
                'sender_name': 'Synthetic',
                'status': 'VALIDATED',
                'actions': [],
                'issues': [],
                'revisions': [],
                'extraction': {},
              }),
              200,
            );
          }),
        );
        addTearDown(api.close);
        await tester.pumpWidget(
          MaterialApp(
            home: ReviewDetailPage(api: api, taskId: 'task'),
          ),
        );
        await tester.pumpAndSettle();
        expect(photos, hasLength(1));
        expect(photos.single.queryParameters, {'variant': 'preview'});
        if (previewFails) {
          expect(
            find.textContaining('Preview belum dapat dimuat'),
            findsOneWidget,
          );
        }
        await tester.tap(find.text('Buka foto asli'));
        await tester.pumpAndSettle();
        expect(photos, hasLength(2));
        expect(photos.last.queryParameters, isEmpty);
        expect(find.byType(InteractiveViewer), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Tutup foto asli'));
        await tester.pumpAndSettle();
        expect(find.byType(InteractiveViewer), findsNothing);
      },
    );
  }
}
