import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/features/kloter/lot_closure_page.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';

final scope = FactoryScope.fromJson({
  'tenantId': 'tenant',
  'tenantName': 'Tenant',
  'factoryId': 'factory',
  'factoryName': 'Pabrik Uji',
});
const root = '/tenants/tenant/factories/factory/lots/lot/closure';
const time = '2026-11-17T01:00:00Z';

Future<void> press(WidgetTester tester, String text) async {
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> mount(WidgetTester tester, ReviewApi api) async {
  await tester.pumpWidget(
    MaterialApp(
      home: LotClosurePage(api: api, scope: scope, lotId: 'lot'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'close and reopen reload status, validate reasons and handle a stale closure',
    (tester) async {
      var closed = false;
      var closureId = 'closure-1';
      final history = <Json>[];
      final writes = <http.Request>[];
      final api = ReviewApi(
        'fixture',
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer fixture');
          expect(request.url.path, startsWith(root));
          if (request.method == 'POST') {
            writes.add(request);
            final body = jsonDecode(request.body) as Json;
            expect(body, isNot(contains('synthetic')));
            if (request.url.path.endsWith('/reopen')) {
              if (body['closureId'] != closureId) {
                return http.Response('{}', 409);
              }
              closed = false;
              history.last.addAll({
                'reopenedAt': time,
                'reopenedBy': 'owner',
                'reason': body['reason'],
              });
              return http.Response(
                jsonEncode({'closureId': closureId, 'reason': body['reason']}),
                200,
              );
            }
            expect(body, isEmpty);
            closed = true;
            history.add({
              'id': closureId,
              'closedAt': time,
              'closedBy': 'admin',
              'reopenedAt': null,
              'reopenedBy': null,
              'reason': null,
            });
            return http.Response(
              jsonEncode({'status': 'closed', 'closureId': closureId}),
              200,
            );
          }
          if (request.url.path.endsWith('/history')) {
            return http.Response(
              jsonEncode({
                'items': history.reversed.toList(),
                'total': history.length,
                'limit': 20,
                'offset': 0,
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'status': closed ? 'closed' : 'open',
              'closureId': closed ? closureId : null,
              'closedAt': closed ? time : null,
              'closedBy': closed ? 'admin' : null,
            }),
            200,
          );
        }),
      );
      await mount(tester, api);
      expect(find.text('Terbuka'), findsOneWidget);
      await press(tester, 'Tutup kloter');
      await press(tester, 'Batal');
      expect(writes, isEmpty);
      await press(tester, 'Tutup kloter');
      await press(tester, 'Tutup kloter');
      expect(writes, hasLength(1));
      expect(find.text('Ditutup'), findsOneWidget);
      expect(find.text('Penutupan aktif'), findsOneWidget);
      await press(tester, 'Buka kembali kloter');
      await press(tester, 'Buka kembali');
      expect(
        find.text('Isi alasan tanpa baris baru atau karakter kontrol.'),
        findsOneWidget,
      );
      expect(writes, hasLength(1));
      await press(tester, 'Batal');
      expect(writes, hasLength(1));

      // Another reviewer reopened and closed the lot while this page was open.
      closureId = 'closure-2';
      await press(tester, 'Buka kembali kloter');
      await tester.enterText(find.byType(TextFormField), ' Periksa transfer ');
      await press(tester, 'Buka kembali');
      expect(jsonDecode(writes.last.body), {
        'closureId': 'closure-1',
        'reason': 'Periksa transfer',
      });
      expect(
        find.textContaining('Penutupan atau alasan sudah berubah.'),
        findsOneWidget,
      );
      expect(find.text('Ditutup'), findsOneWidget);
      await press(tester, 'Buka kembali kloter');
      await tester.enterText(find.byType(TextFormField), 'Periksa transfer');
      await press(tester, 'Buka kembali');
      expect(jsonDecode(writes.last.body), {
        'closureId': 'closure-2',
        'reason': 'Periksa transfer',
      });
      expect(find.text('Terbuka'), findsOneWidget);
      await press(tester, 'Sudah dibuka kembali');
      await tester.ensureVisible(find.text('Periksa transfer'));
      expect(find.text('Periksa transfer'), findsOneWidget);
      expect(find.text('Dibuka kembali oleh'), findsOneWidget);
      expect(find.text('owner'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );

  for (final code in [409, 503]) {
    testWidgets(
      'closure refusal $code keeps current status and shows actionable feedback',
      (tester) async {
        var writes = 0;
        final api = ReviewApi(
          'fixture',
          client: MockClient((request) async {
            if (request.method == 'POST') {
              writes++;
              return http.Response('{}', code);
            }
            return http.Response(
              jsonEncode(
                request.url.path.endsWith('/history')
                    ? {'items': [], 'total': 0, 'limit': 20, 'offset': 0}
                    : {'status': 'open', 'closureId': null},
              ),
              200,
            );
          }),
        );
        await mount(tester, api);
        await press(tester, 'Tutup kloter');
        await press(tester, 'Tutup kloter');
        expect(writes, 1);
        expect(find.text('Terbuka'), findsOneWidget);
        expect(
          find.textContaining(
            code == 409
                ? 'Kloter belum dapat ditutup.'
                : 'Pemeriksaan penutupan belum tersedia.',
          ),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        api.close();
      },
    );
  }

  testWidgets(
    'pending writes cannot repeat and uncertain responses use the refreshed server status',
    (tester) async {
      var writes = 0;
      var closed = false;
      final response = Completer<http.Response>();
      final api = ReviewApi(
        'fixture',
        client: MockClient((request) async {
          if (request.method == 'POST') {
            writes++;
            return response.future;
          }
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('/history')
                  ? {'items': [], 'total': 0, 'limit': 20, 'offset': 0}
                  : {
                      'status': closed ? 'closed' : 'open',
                      'closureId': closed ? 'new' : null,
                      'closedBy': 'admin',
                      'closedAt': time,
                    },
            ),
            200,
          );
        }),
      );
      await mount(tester, api);
      await press(tester, 'Tutup kloter');
      await tester.tap(find.text('Tutup kloter').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(writes, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Tutup kloter'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton &&
                    widget.tooltip == 'Muat ulang penutupan',
              ),
            )
            .onPressed,
        isNull,
      );
      closed = true;
      response.completeError(TimeoutException('Synthetic response was lost.'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.text('Ditutup'), findsOneWidget);
      expect(find.text('Buka kembali kloter'), findsOneWidget);
      expect(
        find.textContaining('Hasil permintaan belum terkonfirmasi.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );

  testWidgets(
    'history pages retain server actors and reasons, while a read denial disables actions',
    (tester) async {
      final offsets = <String>[];
      var denied = false;
      final api = ReviewApi(
        'fixture',
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.headers['Authorization'], 'Bearer fixture');
          expect(request.url.path, startsWith(root));
          if (denied) return http.Response('{}', 403);
          if (request.url.path.endsWith('/history')) {
            final offset = request.url.queryParameters['offset']!;
            offsets.add(offset);
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'id': 'cycle-$offset',
                    'closedAt': time,
                    'closedBy': 'admin-$offset',
                    'reopenedAt': time,
                    'reopenedBy': 'owner-$offset',
                    'reason': 'Alasan halaman $offset',
                  },
                ],
                'total': 21,
                'limit': 20,
                'offset': int.parse(offset),
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({'status': 'open', 'closureId': null}),
            200,
          );
        }),
      );
      await mount(tester, api);
      await press(tester, 'Berikutnya');
      expect(offsets.last, '20');
      await press(tester, 'Sudah dibuka kembali');
      await tester.ensureVisible(find.text('Alasan halaman 20'));
      expect(find.text('Alasan halaman 20'), findsOneWidget);
      expect(find.text('owner-20'), findsOneWidget);
      await press(tester, 'Sebelumnya');
      expect(offsets.last, '0');
      denied = true;
      await tester.tap(find.byTooltip('Muat ulang penutupan'));
      await tester.pumpAndSettle();
      expect(find.text('Data tidak tersedia untuk akun ini.'), findsOneWidget);
      expect(find.text('Tutup kloter'), findsNothing);
      expect(find.text('Buka kembali kloter'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      api.close();
    },
  );
}
