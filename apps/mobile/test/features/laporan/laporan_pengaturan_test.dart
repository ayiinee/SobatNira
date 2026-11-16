import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      inter.addFont(
        rootBundle.load('assets/sobatnira/fonts/Inter-$weight.ttf'),
      );
    }
    await inter.load();
  });

  Future<void> openDemo(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 853));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SobatNiraApp());
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('Laporan berpindah tab, filter, dan detail lokal', (
    tester,
  ) async {
    await openDemo(tester);
    await tap(tester, find.bySemanticsLabel('Laporan'));
    expect(find.text('Gula final'), findsWidgets);
    expect(find.text('Tebu diterima'), findsOneWidget);
    expect(find.text('Rendemen'), findsWidgets);

    await tap(tester, find.bySemanticsLabel('Filter tanggal laporan'));
    await tap(tester, find.text('Hari ini'));
    expect(find.text('Data tidak ditemukan'), findsOneWidget);
    await tap(tester, find.bySemanticsLabel('Filter tanggal laporan'));
    await tap(tester, find.text('Reset'));
    expect(find.text('Sugeng'), findsOneWidget);

    await tap(tester, find.text('Grade').first);
    expect(find.text('Komposisi Grade'), findsOneWidget);
    await tap(tester, find.text('Grade A').last);
    expect(find.text('Detail Grade'), findsOneWidget);
    expect(find.text('Kontribusi per kloter'), findsOneWidget);

    await tap(tester, find.byTooltip('Kembali'));
    await tap(tester, find.text('Margin'));
    expect(find.text('Margin Produksi'), findsOneWidget);
    await tap(tester, find.text('Sugeng'));
    expect(find.text('Margin kloter'), findsOneWidget);
    expect(find.text('Rincian perhitungan'), findsOneWidget);
  });

  testWidgets('Pengaturan menyimpan harga lokal dan membuka placeholder', (
    tester,
  ) async {
    await openDemo(tester);
    await tap(tester, find.bySemanticsLabel('Pengaturan'));
    expect(find.text('Pak Putu Alvin'), findsOneWidget);
    expect(find.text('Harga & Biaya'), findsOneWidget);

    await tap(tester, find.text('Harga & Biaya'));
    expect(find.text('Harga per grade'), findsOneWidget);
    expect(find.text('Simpan perubahan'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '21.000');
    await tap(tester, find.text('Simpan perubahan'));
    expect(
      find.text('Perubahan harga tersimpan selama sesi demo'),
      findsOneWidget,
    );

    await tap(tester, find.byTooltip('Kembali'));
    await tap(tester, find.text('Identitas pabrik'));
    expect(
      find.text('Detail konfigurasi tersedia pada tahap berikutnya.'),
      findsOneWidget,
    );
  });
}
