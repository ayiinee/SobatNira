import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/features/auth/login_pages.dart';
import 'package:sobatnira/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('aset logo Ukaisya tersedia di bundle Flutter', () async {
    final logo = await rootBundle.load('assets/sobatnira/art/ukaisya-logo.png');
    expect(logo.lengthInBytes, greaterThan(0));
  });

  testWidgets('aplikasi langsung membuka Beranda tanpa onboarding atau login', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 853));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SobatNiraApp());
    await tester.pumpAndSettle();
    expect(find.text('Tebu diterima'), findsOneWidget);
    expect(find.byType(LoginWelcomePage), findsNothing);
    expect(find.byType(LoginFormPage), findsNothing);
    expect(
      Navigator.of(tester.element(find.text('Tebu diterima'))).canPop(),
      isFalse,
    );
    await tester.pumpWidget(const SobatNiraApp(key: ValueKey('restart')));
    await tester.pumpAndSettle();
    expect(find.text('Tebu diterima'), findsOneWidget);
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
