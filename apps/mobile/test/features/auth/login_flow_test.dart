import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/features/auth/login_pages.dart';
import 'package:sobatnira/main.dart';

import '../../support/demo_login.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('aset logo Ukaisya tersedia di bundle Flutter', () async {
    final logo = await rootBundle.load('assets/sobatnira/art/ukaisya-logo.png');
    expect(logo.lengthInBytes, greaterThan(0));
  });

  testWidgets('login demo memvalidasi form dan membuka Beranda', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 853));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SobatNiraApp());
    await tester.pumpAndSettle();

    expect(find.byType(LoginWelcomePage), findsOneWidget);
    expect(
      find.bySemanticsLabel('Ukaisya, PT Tiga Dewi Timur Raya'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Beranda'), findsNothing);
    await openDemoLogin(tester);
    expect(find.byType(LoginFormPage), findsOneWidget);
    expect(
      find.bySemanticsLabel('Ukaisya, PT Tiga Dewi Timur Raya'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Beranda'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(LoginWelcomePage), findsOneWidget);
    await openDemoLogin(tester);

    final submit = find.widgetWithText(FilledButton, 'Masuk');
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Masukkan nama pengguna.'), findsOneWidget);
    expect(find.text('Masukkan kata sandi.'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
      isTrue,
    );

    final remember = find.byType(Checkbox);
    expect(tester.widget<Checkbox>(remember).value, isFalse);
    await tester.tap(find.text('Ingat saya'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(remember).value, isTrue);

    await tester.tap(find.text('Lupa kata sandi?'));
    await tester.pumpAndSettle();
    expect(find.text('Belum tersedia di demo'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await submitDemoLogin(tester);
    expect(find.text('Tebu diterima'), findsOneWidget);
    expect(find.byType(LoginWelcomePage), findsNothing);
    expect(find.byType(LoginFormPage), findsNothing);
    expect(
      Navigator.of(tester.element(find.text('Tebu diterima'))).canPop(),
      isFalse,
    );

    await tester.pumpWidget(const SobatNiraApp(key: ValueKey('restart')));
    await tester.pumpAndSettle();
    expect(find.byType(LoginWelcomePage), findsOneWidget);
    await openDemoLogin(tester);
    expect(tester.widget<Checkbox>(remember).value, isFalse);
  });

  testWidgets('form bisa digulir saat keyboard memakai ruang layar', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    tester.view.viewInsets = const FakeViewPadding(bottom: 305);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: LoginFormPage(onSubmit: () {})));
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(FilledButton, 'Masuk');
    expect(submit.hitTestable(), findsNothing);
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    expect(submit.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
