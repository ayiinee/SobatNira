import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';
import 'package:sobatnira/main.dart';

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder field(String label) => find.widgetWithText(TextFormField, label);

void main() {
  testWidgets('manages WhatsApp operators in the selected factory', (
    tester,
  ) async {
    const base = '/tenants/tenant/factories/pabrik-b/operators';
    const phone = '+12025550742';
    const original = {'displayName': 'Operator Uji', 'isActive': true};
    const deactivated = {'displayName': 'Operator Uji B', 'isActive': false};
    const created = {'id': 'operator-b', 'phoneE164': phone, ...original};
    final requests = <http.Request>[];
    Json? operator;
    var duplicate = true;
    final api = ReviewApi(
      'fixture',
      client: MockClient((request) async {
        requests.add(request);
        expect(request.headers['Authorization'], 'Bearer fixture');
        final path = request.url.path;
        final query = request.url.queryParameters;
        http.Response page(List<Json> items, {int? total}) => http.Response(
          jsonEncode({
            'items': items,
            'total': total ?? items.length,
            'limit': 20,
            'offset': int.parse(query['offset'] ?? '0'),
          }),
          200,
        );
        if (path == '/auth/me') {
          return http.Response(
            jsonEncode({
              'access': [
                for (final factory in ['a', 'b'])
                  {
                    'tenantId': 'tenant',
                    'tenantName': 'Tenant',
                    'factoryId': 'pabrik-$factory',
                    'factoryName': 'Pabrik ${factory.toUpperCase()}',
                  },
              ],
            }),
            200,
          );
        }
        if (path.endsWith('/lots')) return page([]);
        if (path.endsWith('/production-report')) {
          return http.Response(
            jsonEncode({'items': [], 'totals': {}, 'grades': []}),
            200,
          );
        }
        if (path == base && request.method == 'GET') {
          return page([
            if (operator != null &&
                (query['isActive'] == null ||
                    query['isActive'] == '${operator!['isActive']}'))
              operator!,
          ]);
        }
        if (path == base && request.method == 'POST') {
          expect(jsonDecode(request.body), {
            'displayName': 'Operator Uji',
            'phoneE164': phone,
          });
          if (duplicate) return http.Response('{}', 409);
          operator = Map.from(created);
          return http.Response(jsonEncode(operator), 201);
        }
        if (path == '$base/operator-b' && request.method == 'PATCH') {
          final change = jsonDecode(request.body) as Json;
          expect(
            change,
            operator!['isActive'] == true ? deactivated : {'isActive': true},
          );
          operator!.addAll(change);
          return http.Response(jsonEncode(operator), 200);
        }
        if (path == '$base/operator-b/history') {
          final firstPage = query['offset'] == '0';
          return page([
            {
              'action': firstPage ? 'updated' : 'created',
              'actorId': 'fixture-actor',
              'occurredAt': '2026-11-17T01:00:00Z',
              'before': firstPage ? original : null,
              'after': firstPage ? deactivated : original,
            },
          ], total: 21);
        }
        throw StateError('Unexpected request ${request.method} $path');
      }),
    );

    await tester.pumpWidget(
      SobatNiraApp(configurationErrors: const [], signIn: (_, _) async => api),
    );
    await tap(tester, find.text('Masuk'));
    await tester.enterText(
      find.byType(TextField).first,
      'admin@example.invalid',
    );
    await tester.enterText(find.byType(TextField).last, 'fixture-password');
    await tap(tester, find.text('Masuk'));
    await tap(tester, find.byTooltip('Pilih pabrik'));
    await tap(tester, find.text('Pabrik B'));
    await tap(tester, find.bySemanticsLabel('Pengaturan'));
    await tap(tester, find.bySemanticsLabel('Pegawai & WhatsApp'));
    expect(requests.last.url.path, base);
    expect(find.text('Data tidak ditemukan.'), findsOneWidget);
    await tap(tester, find.text('Tambah operator WhatsApp'));
    await tester.enterText(field('Nama'), 'Operator Uji');
    await tester.enterText(field('Nomor WhatsApp'), '081234567890');
    await tap(tester, find.text('Simpan'));
    expect(
      find.textContaining('Masukkan nomor dengan kode negara'),
      findsOneWidget,
    );
    expect(requests.where((request) => request.method == 'POST'), isEmpty);
    await tester.enterText(field('Nomor WhatsApp'), phone);
    await tap(tester, find.text('Simpan'));
    expect(find.text('Nomor WhatsApp sudah terdaftar.'), findsOneWidget);
    duplicate = false;
    await tap(tester, find.text('Simpan'));
    expect(find.text('$phone · Aktif'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '+1202');
    await tap(tester, find.byTooltip('Cari'));
    expect(requests.last.url.queryParameters, containsPair('q', '+1202'));
    await tap(tester, find.byTooltip('Edit operator'));
    expect(field('Nomor WhatsApp'), findsNothing);
    await tester.enterText(field('Nama'), 'Operator Uji B');
    await tap(tester, find.byType(SwitchListTile));
    await tap(tester, find.text('Simpan'));
    expect(find.text('$phone · Nonaktif'), findsOneWidget);

    await tap(tester, find.byTooltip('Riwayat operator'));
    expect(find.text('Operator Uji → Operator Uji B'), findsOneWidget);
    expect(find.text('Aktif → Nonaktif'), findsOneWidget);
    expect(find.text('ID akun fixture-actor'), findsOneWidget);
    await tap(tester, find.byTooltip('Berikutnya'));
    expect(requests.last.url.queryParameters, containsPair('offset', '20'));
    expect(find.text('Operator ditambahkan'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tap(tester, find.text('Semua status'));
    await tap(tester, find.text('Nonaktif').last);
    expect(
      requests.last.url.queryParameters,
      containsPair('isActive', 'false'),
    );

    await tap(tester, find.byTooltip('Edit operator'));
    await tap(tester, find.byType(SwitchListTile));
    await tap(tester, find.text('Simpan'));
    expect(find.text('$phone · Nonaktif'), findsNothing);
    expect(find.text('Data tidak ditemukan.'), findsOneWidget);
  });
}
