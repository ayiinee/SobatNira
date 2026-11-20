import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sobatnira/features/auth/login_pages.dart';
import 'package:sobatnira/features/kloter/connected_kloter_page.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';
import 'package:sobatnira/main.dart';
import 'package:sobatnira/widgets/adaptive_value.dart';
import 'package:sobatnira/sobatnira_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('aset logo Ukaisya tersedia di bundle Flutter', () async {
    final logo = await rootBundle.load('assets/sobatnira/art/ukaisya-logo.png');
    expect(logo.lengthInBytes, greaterThan(0));
  });

  testWidgets('entri utama meminta konfigurasi saat API belum disiapkan', (
    tester,
  ) async {
    await tester.pumpWidget(
      const SobatNiraApp(configurationErrors: ['SUPABASE_URL']),
    );
    await tester.pumpAndSettle();
    expect(find.text('Layanan masuk belum dikonfigurasi.'), findsOneWidget);
    expect(find.text('Tebu diterima'), findsNothing);
  });

  testWidgets('demo offline langsung membuka Beranda', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 853));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SobatNiraApp(connected: false));
    await tester.pumpAndSettle();
    final caneSummary = find.text('Tebu diterima');
    expect(caneSummary, findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is NiraValue && widget.value == '17.990 kg',
      ),
      findsOneWidget,
    );
    expect(find.byType(LoginWelcomePage), findsNothing);
    expect(find.byType(LoginFormPage), findsNothing);
    expect(Navigator.of(tester.element(caneSummary)).canPop(), isFalse);
    await tester.pumpWidget(
      const SobatNiraApp(key: ValueKey('restart'), connected: false),
    );
    await tester.pumpAndSettle();
    expect(caneSummary, findsOneWidget);
    expect(find.byType(LoginWelcomePage), findsNothing);
    expect(find.byType(LoginFormPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('form bisa digulir saat keyboard memakai ruang layar', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    tester.view.viewInsets = const FakeViewPadding(bottom: 305);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: niraTheme(),
        home: MediaQuery(
          data: MediaQueryData.fromView(
            tester.view,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: LoginFormPage(onSubmit: (_, _) {}, onBack: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(FilledButton, 'Masuk');
    expect(submit.hitTestable(), findsNothing);
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    expect(submit.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mode terhubung membuka form dan bisa kembali ke sambutan', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ConnectedKloterPage()));
    expect(find.byType(LoginWelcomePage), findsOneWidget);
    await _openLogin(tester);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(LoginWelcomePage), findsOneWidget);
    await _openLogin(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(LoginWelcomePage), findsOneWidget);
  });

  testWidgets(
    'form fokus pada input yang salah dan mengendalikan visibilitas sandi',
    (tester) async {
      final submissions = <(String, String)>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: niraTheme(),
          home: LoginFormPage(
            onBack: () {},
            onSubmit: (email, password) => submissions.add((email, password)),
          ),
        ),
      );
      await tester.tap(find.text('Masuk'));
      await tester.pumpAndSettle();
      expect(find.text('Masukkan email.'), findsOneWidget);
      expect(find.text('Masukkan kata sandi.'), findsOneWidget);
      expect(_editable(tester, 0).focusNode.hasFocus, isTrue);
      await tester.enterText(find.byType(TextFormField).first, 'bukan-email');
      await tester.pumpAndSettle();
      expect(
        find.text('Masukkan email dengan format yang benar.'),
        findsOneWidget,
      );
      expect(submissions, isEmpty);

      await tester.enterText(
        find.byType(TextFormField).first,
        '  admin@example.invalid  ',
      );
      await tester.tap(find.text('Masuk'));
      await tester.pumpAndSettle();
      expect(_editable(tester, 1).focusNode.hasFocus, isTrue);
      await tester.enterText(find.byType(TextFormField).last, ' sandi contoh ');
      expect(_editable(tester, 1).obscureText, isTrue);
      await tester.tap(find.byTooltip('Tampilkan kata sandi'));
      await tester.pump();
      expect(_editable(tester, 1).obscureText, isFalse);
      await tester.tap(find.byTooltip('Sembunyikan kata sandi'));
      await tester.pump();
      expect(_editable(tester, 1).obscureText, isTrue);
      await tester.tap(find.text('Masuk'));
      expect(submissions, [('admin@example.invalid', ' sandi contoh ')]);
    },
  );

  testWidgets('hanya satu permintaan aktif dan error masuk dibedakan', (
    tester,
  ) async {
    final attempts = <Completer<ReviewApi>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ConnectedKloterPage(
          signIn: (_, _) {
            final attempt = Completer<ReviewApi>();
            attempts.add(attempt);
            return attempt.future;
          },
        ),
      ),
    );
    await _openLogin(tester);
    await _fillCredentials(tester);
    await tester.tap(find.text('Masuk'));
    await tester.tap(find.text('Masuk'));
    await tester.pump();
    expect(attempts, hasLength(1));
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.text('Memeriksa akun…'), findsOneWidget);
    const fallback =
        'Belum bisa masuk. Coba lagi atau hubungi pengelola pabrik.';
    final cases = [
      (
        http.Response('{"error_code":"invalid_credentials"}', 400),
        'Email atau kata sandi tidak cocok.',
      ),
      (
        http.Response('{"error_code":"email_not_confirmed"}', 400),
        'Email belum dikonfirmasi. Periksa kotak masuk atau hubungi pengelola pabrik.',
      ),
      (
        http.Response('{"error_code":"user_banned"}', 403),
        'Akun ini tidak bisa digunakan. Hubungi pengelola pabrik.',
      ),
      (
        http.Response('Too many requests', 429),
        'Terlalu banyak percobaan. Tunggu sebentar sebelum mencoba lagi.',
      ),
      (
        http.Response('{"error_code":"unknown","msg":"Raw error"}', 401),
        fallback,
      ),
      (http.Response('<html>Raw error</html>', 400), fallback),
      (
        http.Response('{}', 503),
        'Belum bisa masuk. Periksa koneksi dan coba lagi.',
      ),
    ];
    for (final (response, message) in cases) {
      if (attempts.last.isCompleted) await tester.tap(find.text('Masuk'));
      attempts.last.completeError(ReviewApiError.fromSignInResponse(response));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('Raw error'), findsNothing);
    }
    expect(attempts, hasLength(cases.length));
  });

  testWidgets(
    'ulang pemeriksaan akses memakai sesi yang sama dan akun tanpa akses bisa keluar',
    (tester) async {
      var checks = 0;
      var signIns = 0;
      final api = ReviewApi(
        'fixture',
        client: MockClient((request) async {
          expect(request.url.path, '/auth/me');
          checks++;
          return checks == 1 ? http.Response('{}', 503) : _json({'access': []});
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ConnectedKloterPage(
            signIn: (_, _) async {
              signIns++;
              return api;
            },
          ),
        ),
      );
      await _openLogin(tester);
      await _fillCredentials(tester);
      await tester.tap(find.text('Masuk'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(checks, 2);
      expect(signIns, 1);
      expect(
        find.text('Akun ini belum memiliki akses pabrik aktif.'),
        findsOneWidget,
      );
      expect(find.text('Tambah kloter'), findsNothing);
      await tester.tap(find.text('Keluar'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginFormPage), findsOneWidget);
      expect(_editable(tester, 1).controller.text, isEmpty);
    },
  );

  testWidgets(
    '403 mempertahankan sesi dan 401 dari Pekerjaan kembali ke form masuk',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 853));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = ReviewApi(
        'fixture',
        client: MockClient((request) async {
          return switch (request.url.path) {
            '/auth/me' => _json({
              'access': [
                {
                  'tenantId': 'tenant',
                  'tenantName': 'Tenant',
                  'factoryId': 'factory',
                  'factoryName': 'Pabrik',
                },
              ],
            }),
            '/tenants/tenant/factories/factory/production/production-report' =>
              _json({
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
              }),
            '/tenants/tenant/factories/factory/lots' => http.Response(
              '{}',
              403,
            ),
            '/api/v1/mobile/review-tasks' => http.Response('{}', 401),
            '/api/v1/mobile/review-notifications' => _json({'unread_count': 0}),
            _ => throw StateError('Unexpected route ${request.url.path}'),
          };
        }),
      );
      await tester.pumpWidget(
        MaterialApp(home: ConnectedKloterPage(signIn: (_, _) async => api)),
      );
      await _openLogin(tester);
      await _fillCredentials(tester);
      await tester.tap(find.text('Masuk'));
      await tester.pumpAndSettle();
      expect(find.text('Data tidak tersedia untuk akun ini.'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Pengaturan'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Pekerjaan'), 200);
      await tester.tap(find.text('Pekerjaan'));
      await tester.pumpAndSettle();
      expect(find.text('Sesi berakhir. Masuk kembali.'), findsOneWidget);
      expect(find.byType(LoginFormPage), findsOneWidget);
      expect(
        Navigator.of(tester.element(find.byType(LoginFormPage))).canPop(),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _openLogin(WidgetTester tester) async {
  await tester.tap(find.text('Masuk'));
  await tester.pumpAndSettle();
  expect(find.byType(LoginFormPage), findsOneWidget);
}

Future<void> _fillCredentials(WidgetTester tester) async {
  await tester.enterText(
    find.byType(TextFormField).first,
    'admin@example.invalid',
  );
  await tester.enterText(find.byType(TextFormField).last, 'fixture-password');
}

EditableText _editable(WidgetTester tester, int index) =>
    tester.widget<EditableText>(find.byType(EditableText).at(index));

http.Response _json(Json body) => http.Response(jsonEncode(body), 200);
