import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/features/bantuan/bantuan_page.dart';
import 'package:sobatnira/main.dart';

void main() {
  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 853));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SobatNiraApp(connected: false));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'operational shortcut and settings share saved prices and cancel drafts',
    (tester) async {
      await open(tester);
      await tap(tester, find.text('Biaya Ops'));
      final cost = find.widgetWithText(TextFormField, 'Biaya Operasional');
      final grade = find.widgetWithText(TextFormField, 'Grade A');
      expect(tester.getTopLeft(cost).dy, lessThan(tester.getTopLeft(grade).dy));
      await tester.enterText(cost, '175000');
      await tap(tester, find.text('Simpan perubahan'));
      expect(tester.widget<TextFormField>(cost).controller!.text, '175.000');
      await tester.pump(const Duration(seconds: 5));
      await tap(tester, find.bySemanticsLabel('Pengaturan'));
      await tap(tester, find.text('Harga & Biaya'));
      expect(tester.widget<TextFormField>(cost).controller!.text, '175.000');
      await tester.enterText(cost, '999999');
      await tap(tester, find.byTooltip('Kembali'));
      await tap(tester, find.bySemanticsLabel('Beranda'));
      await tap(tester, find.text('Biaya Ops'));
      expect(tester.widget<TextFormField>(cost).controller!.text, '175.000');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'help validates and opens the encoded WhatsApp draft, retains failed messages',
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final calls = <MethodCall>[];
      var opened = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return opened;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await open(tester);
      await tap(tester, find.text('Bantuan'));
      await tap(tester, find.text('Kirim via WhatsApp'));
      expect(find.text('Tulis pesan terlebih dahulu.'), findsOneWidget);
      expect(calls, isEmpty);
      const message = 'Halo, gula & biaya?\nTolong cek #kloter 😊';
      await tester.enterText(find.byType(TextFormField), message);
      await tap(tester, find.text('Kirim via WhatsApp'));
      final app = Uri.parse((calls.first.arguments as Map)['url'] as String);
      expect(app.scheme, 'whatsapp');
      expect(app.host, 'send');
      expect(app.queryParameters, {'phone': '6285337236836', 'text': message});
      expect(app.query, contains('%20'));
      expect(calls, hasLength(2));
      final uri = Uri.parse((calls.last.arguments as Map)['url'] as String);
      expect(uri.scheme, 'https');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/6285337236836');
      expect(uri.queryParameters['text'], message);
      expect((calls.last.arguments as Map)['useWebView'], isFalse);
      expect(
        find.text(
          'WhatsApp belum bisa dibuka. Coba lagi atau hubungi nomor di atas.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        message,
      );
      opened = true;
      await tap(tester, find.text('Kirim via WhatsApp'));
      expect(calls, hasLength(3));
      expect((calls.last.arguments as Map)['url'], app.toString());
      expect(
        find.text(
          'WhatsApp belum bisa dibuka. Coba lagi atau hubungi nomor di atas.',
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'support link trims the message and uses the Indonesian country code',
    () {
      final uri = supportWhatsAppUri('  Halo & bantuan\n  ');
      expect(uri.path, '/6285337236836');
      expect(uri.queryParameters['text'], 'Halo & bantuan');
    },
  );

  testWidgets(
    'navigation hides while typing even when web reports no keyboard inset',
    (tester) async {
      await open(tester);
      await tap(tester, find.text('Bantuan'));
      expect(find.bySemanticsLabel('Beranda'), findsOneWidget);
      await tester.tap(find.byType(TextFormField));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Beranda'), findsNothing);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Beranda'), findsOneWidget);
    },
  );
}
