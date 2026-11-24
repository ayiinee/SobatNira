import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';
import 'package:sobatnira/main.dart';

import '../../support/demo_login.dart';

Json _factory(String id, String role) => {
  'tenantId': 'tenant',
  'tenantName': 'Tenant Uji',
  'factoryId': id,
  'factoryName': 'Pabrik $id',
  'role': role,
};

http.Response _json(Object body) => http.Response(jsonEncode(body), 200);

http.Response _production({bool synthetic = false}) => _json({
  'items': [
    if (!synthetic)
      {
        'lotId': 'lot-A',
        'code': 'KLOTER-A',
        'supplier': 'Pemasok Uji',
        'receivedAt': '2026-11-24T07:00:00Z',
        'calculation': {
          'costs': {'operationalRupiah': '125000'},
        },
        'batches': [
          for (final code in ['BATCH-A1', 'BATCH-A2'])
            {
              'code': code,
              'wokNumber': 2,
              'occurredAt': '2026-11-24T08:00:00Z',
              'grades': [
                {'code': 'A', 'weightKg': '12.75', 'pricePerKgRupiah': '20000'},
              ],
            },
        ],
      },
  ],
  'grades': [
    if (!synthetic) {'code': 'A', 'weightKg': '25.5'},
  ],
  'totals': <String, Object>{},
});

Future<void> _openApp(
  WidgetTester tester,
  FutureOr<http.Response?> Function(Uri) override,
) async {
  await tester.binding.setSurfaceSize(const Size(718, 626));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final api = ReviewApi(
    'token-uji',
    client: MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.headers['authorization'], 'Bearer token-uji');
      final uri = request.url;
      final response = await override(uri);
      if (response != null) return response;
      return switch (uri.path) {
        '/auth/me' => _json({
          'access': [_factory('A', 'owner'), _factory('B', 'admin')],
        }),
        '/tenants/tenant/factories/A' => _json({
          'name': 'Pabrik A',
          'role': 'owner',
        }),
        '/tenants/tenant/factories/B' => _json({
          'name': 'Pabrik B',
          'role': 'admin',
        }),
        '/tenants/tenant/factories/A/memberships' => _json({
          'memberships': [
            {'userId': 'akun-aktif-A', 'role': 'owner', 'isActive': true},
            {'userId': 'akun-nonaktif-A', 'role': 'admin', 'isActive': false},
          ],
        }),
        _ when uri.path.endsWith('/lots') => _json({'items': [], 'total': 0}),
        _ when uri.path.endsWith('/production-report') => _production(
          synthetic: uri.queryParameters['synthetic'] == 'true',
        ),
        _ => throw StateError('Rute tes tidak dikenal ${uri.path}'),
      };
    }),
  );
  addTearDown(api.close);
  await tester.pumpWidget(
    SobatNiraApp(
      connected: true,
      configurationErrors: const [],
      signIn: (_, _) async => api,
    ),
  );
  await tester.pumpAndSettle();
  await openDemoLogin(tester);
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'pemilik@example.invalid');
  await tester.enterText(fields.at(1), 'sandi-demo');
  await _tap(tester, find.widgetWithText(FilledButton, 'Masuk'));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _menu(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
  description: 'menu $label',
);

void main() {
  testWidgets('pemilik bisa membuka semua halaman pratinjau', (tester) async {
    final requests = <Uri>[];
    await _openApp(tester, (uri) {
      requests.add(uri);
      return null;
    });
    await _tap(tester, _menu('Pengaturan'));

    for (final (menu, content) in [
      ('Identitas pabrik', 'Tenant Uji'),
      ('Fasilitas Produksi', 'Wajan 2'),
      ('Shift kerja', 'Jadwal sif per pabrik belum tersedia.'),
      ('Hak akses & pengguna', 'Nonaktif'),
      ('Aturan produksi', 'Satu grade dicatat untuk setiap batch.'),
      ('Grade produk', 'Klasifikasi hasil produksi'),
      ('Bahan tambahan (BTP)', 'Daftar BTP per pabrik belum tersedia.'),
      ('Formulir produksi', 'Nota Kedatangan Truk'),
      ('Harga & Biaya', 'KLOTER-A'),
    ]) {
      requests.clear();
      await _tap(tester, _menu(menu));
      expect(find.text(content), findsOneWidget, reason: menu);
      expect(find.text('Simpan perubahan'), findsNothing);
      expect(find.text('Isi biaya'), findsNothing);
      if (menu == 'Grade produk') {
        for (final code in ['A', 'B', 'C']) {
          expect(find.text('Grade $code'), findsOneWidget);
        }
        expect(requests, isEmpty);
      } else if (menu == 'Fasilitas Produksi') {
        expect(find.text('2 batch disahkan'), findsOneWidget);
      } else if (menu == 'Formulir produksi') {
        expect(find.byTooltip('Tambah alias Tanggal'), findsNothing);
        await _tap(tester, find.text('Nota Kedatangan Truk'));
        await _tap(tester, find.text('Nota Produksi').last);
        expect(find.text('shift · Kode atau teks'), findsOneWidget);
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Kembali').hitTestable(), findsOneWidget);
      } else if (menu == 'Harga & Biaya') {
        await _tap(tester, find.text('KLOTER-A'));
        expect(find.text('Komponen biaya'), findsOneWidget);
        expect(find.text('Harga jual per grade'), findsOneWidget);
        expect(find.text('Rp125.000'), findsOneWidget);
        expect(find.text('Rp20.000/kg'), findsOneWidget);
      }
      final back = find.byTooltip('Kembali');
      if (back.evaluate().isEmpty) {
        await tester.scrollUntilVisible(back, -300);
      }
      await _tap(tester, back);
    }
  });

  testWidgets('pindah pabrik membatasi anggota dan biaya sesuai peran', (
    tester,
  ) async {
    final requests = <Uri>[];
    await _openApp(tester, (uri) {
      requests.add(uri);
      return null;
    });
    await _tap(tester, _menu('Pengaturan'));
    await _tap(tester, _menu('Hak akses & pengguna'));
    expect(find.text('ID akun akun-aktif-A'), findsOneWidget);
    await _tap(tester, _menu('Beranda'));
    await _tap(tester, find.byTooltip('Pilih pabrik'));
    await _tap(tester, find.text('Pabrik B'));
    await _tap(tester, _menu('Pengaturan'));
    expect(_menu('Hak akses & pengguna'), findsNothing);

    await _tap(tester, _menu('Identitas pabrik'));
    expect(find.text('Pabrik B'), findsWidgets);
    expect(find.text('ID akun akun-aktif-A'), findsNothing);
    await _tap(tester, find.byTooltip('Kembali'));
    requests.clear();
    await _tap(tester, _menu('Harga & Biaya'));
    expect(
      find.textContaining('tersedia untuk pemilik pabrik'),
      findsOneWidget,
    );
    expect(find.text('Rp125.000'), findsNothing);
    expect(requests, isEmpty);
  });

  testWidgets('semua kode grade terbaca pada layar sempit dengan teks besar', (
    tester,
  ) async {
    await _openApp(tester, (_) => null);
    await _tap(tester, _menu('Pengaturan'));
    final gradeMenu = _menu('Grade produk');
    await tester.scrollUntilVisible(gradeMenu, 220);
    await _tap(tester, gradeMenu);

    await tester.binding.setSurfaceSize(const Size(320, 626));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();

    for (final code in ['A', 'B', 'C']) {
      final label = find.text('Grade $code');
      expect(label, findsOneWidget);
      await tester.ensureVisible(label);
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byType(ListView));
      final bounds = tester.getRect(label);
      expect(
        viewport.contains(bounds.topLeft),
        isTrue,
        reason: 'Grade $code $bounds dalam $viewport',
      );
      expect(
        viewport.contains(bounds.bottomRight),
        isTrue,
        reason: 'Grade $code $bounds dalam $viewport',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pengaturan membedakan gagal muat, coba lagi dan akses ditolak', (
    tester,
  ) async {
    var attempts = 0;
    await _openApp(tester, (uri) {
      if (uri.path.endsWith('/factories/A') && attempts++ == 0) {
        return http.Response('', 503);
      }
      if (uri.path.endsWith('/memberships')) return http.Response('', 403);
      return null;
    });
    await _tap(tester, _menu('Pengaturan'));
    await _tap(tester, _menu('Identitas pabrik'));
    expect(find.text('Data pengaturan belum bisa dimuat.'), findsOneWidget);
    await _tap(tester, find.text('Coba lagi'));
    expect(find.text('Tenant Uji'), findsOneWidget);
    await _tap(tester, find.byTooltip('Kembali'));
    await _tap(tester, _menu('Hak akses & pengguna'));
    expect(
      find.text('Akun ini tidak memiliki akses ke data ini.'),
      findsOneWidget,
    );
    expect(find.text('Coba lagi'), findsNothing);
  });

  testWidgets('respons lama tidak muncul setelah beralih ke data contoh', (
    tester,
  ) async {
    final delayed = Completer<http.Response>();
    var hold = false;
    await _openApp(tester, (uri) {
      if (hold &&
          uri.path.endsWith('/production-report') &&
          uri.queryParameters['synthetic'] == 'false') {
        return delayed.future;
      }
      return null;
    });
    await _tap(tester, _menu('Pengaturan'));
    hold = true;
    await tester.tap(_menu('Fasilitas Produksi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Memuat pengaturan…'), findsWidgets);
    hold = false;
    await _tap(tester, find.byTooltip('Kembali'));
    await _tap(tester, _menu('Beranda'));
    await _tap(tester, find.text('Rekap'));
    await _tap(tester, find.text('Tampilkan data contoh'));
    await _tap(tester, _menu('Pengaturan'));
    await _tap(tester, _menu('Fasilitas Produksi'));
    expect(find.textContaining('Data sintetis'), findsOneWidget);
    expect(find.text('Belum ada wajan pada batch sah.'), findsOneWidget);
    delayed.complete(_production());
    await tester.pumpAndSettle();
    expect(find.text('Wajan 2'), findsNothing);
  });
}
