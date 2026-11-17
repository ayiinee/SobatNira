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

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> settings(WidgetTester tester) async {
    await openDemo(tester);
    await tap(tester, find.bySemanticsLabel('Pengaturan'));
  }

  Future<void> select(WidgetTester tester, String label, String value) async {
    await tap(tester, find.byKey(ValueKey(label)));
    await tap(tester, find.text(value).last);
  }

  testWidgets('Laporan berpindah tab, filter, dan detail lokal', (
    tester,
  ) async {
    await openDemo(tester);
    await tap(tester, find.bySemanticsLabel('Laporan'));
    expect(find.text('Gula final'), findsWidgets);
    expect(find.text('Tebu diterima'), findsOneWidget);
    expect(find.text('Rendemen'), findsWidgets);
    expect(find.byType(TextField), findsNothing);
    expect(
      tester.getCenter(find.bySemanticsLabel('Filter tanggal laporan')).dx,
      greaterThan(tester.getCenter(find.byTooltip('Jenis grafik')).dx),
    );

    await tap(tester, find.bySemanticsLabel('Filter tanggal laporan'));
    await tap(tester, find.text('Hari ini'));
    expect(find.text('Data tidak ditemukan'), findsOneWidget);
    await tap(tester, find.bySemanticsLabel('Filter tanggal laporan'));
    await tap(tester, find.text('Reset'));
    expect(find.text('Sugeng'), findsOneWidget);

    await tap(tester, find.byTooltip('Jenis grafik'));
    await tap(tester, find.text('Grade').last);
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

  testWidgets('Semua menu Pengaturan membuka layar dengan konten', (
    tester,
  ) async {
    await settings(tester);
    expect(find.text('Pak Putu Alvin'), findsOneWidget);
    const pages = {
      'Identitas pabrik': 'Nama pabrik',
      'Fasilitas Produksi': 'Tambah wajan',
      'Pegawai & WhatsApp': 'Tambah operator',
      'Shift kerja': 'Tambah shift',
      'Hak akses & pengguna': 'Tambah akun',
      'Aturan produksi': 'Batas volume batch',
      'Grade produk': 'Tambah grade',
      'Bahan tambahan (BTP)': 'Tambah bahan',
      'Formulir produksi': 'Nota Kedatangan Truk',
      'Harga & Biaya': 'Harga per grade',
    };
    for (final page in pages.entries) {
      await tap(tester, find.text(page.key));
      expect(find.text(page.value), findsOneWidget, reason: page.key);
      await tap(tester, find.byTooltip('Kembali'));
      expect(tester.takeException(), isNull, reason: page.key);
    }
  });

  testWidgets('Identitas membuang draf batal dan mereset data pada sesi baru', (
    tester,
  ) async {
    await settings(tester);
    await tap(tester, find.text('Identitas pabrik'));
    await tester.enterText(field('Nama pabrik'), '');
    await tap(tester, find.text('Simpan perubahan'));
    expect(find.text('Isi kolom ini.'), findsOneWidget);
    await tester.enterText(field('Nama pabrik'), 'Draf Batal');
    await tap(tester, find.text('Batal'));
    await tap(tester, find.text('Identitas pabrik'));
    expect(find.text('Pabrik Demo'), findsOneWidget);

    await tester.enterText(field('Nama pabrik'), 'Pabrik Uji');
    await tap(tester, find.text('Simpan perubahan'));
    await tap(tester, find.byTooltip('Kembali'));
    await tap(tester, find.text('Identitas pabrik'));
    expect(find.text('Pabrik Uji'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await settings(tester);
    await tap(tester, find.text('Identitas pabrik'));
    expect(find.text('Pabrik Demo'), findsOneWidget);
  });

  testWidgets('Daftar wajan menolak duplikat dan menerima kapasitas desimal', (
    tester,
  ) async {
    await settings(tester);
    await tap(tester, find.text('Fasilitas Produksi'));
    await tap(tester, find.text('Tambah wajan'));
    await tester.enterText(field('Nama wajan'), 'wajan 1');
    await tester.enterText(field('Kapasitas'), '-2');
    await tap(tester, find.text('Simpan perubahan'));
    expect(find.text('Nilai ini sudah digunakan.'), findsOneWidget);
    expect(find.text('Masukkan angka lebih dari nol.'), findsOneWidget);
    await tester.enterText(field('Nama wajan'), 'Wajan Uji');
    await tester.enterText(field('Kapasitas'), '112,5');
    await tap(tester, find.text('Simpan perubahan'));
    expect(find.text('Wajan Uji'), findsOneWidget);
    expect(find.textContaining('112,5 L'), findsOneWidget);
  });

  testWidgets(
    'Perubahan peran memerlukan konfirmasi dan akun ini terlindungi',
    (tester) async {
      await settings(tester);
      await tap(tester, find.text('Hak akses & pengguna'));
      await tap(tester, find.text('Pak Putu Alvin (akun ini)'));
      for (final label in ['Peran', 'Status']) {
        final dropdown = tester.widget<DropdownButtonFormField<String>>(
          find.byKey(ValueKey(label)),
        );
        expect(dropdown.onChanged, isNull);
      }
      await tap(tester, find.text('Batal'));

      await tap(tester, find.text('Admin Demo'));
      await select(tester, 'Peran', 'Owner/Manager');
      await tap(tester, find.text('Simpan perubahan'));
      expect(find.text('Konfirmasi perubahan'), findsOneWidget);
      await tap(tester, find.text('Batal').last);
      expect(find.text('Edit akun'), findsOneWidget);
      await tap(tester, find.text('Simpan perubahan'));
      await tap(tester, find.text('Konfirmasi'));
      expect(
        find.textContaining('Owner/Manager\nadmin@example.invalid'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Grade baru berbagi harga ID yang sama saat status berubah', (
    tester,
  ) async {
    await settings(tester);
    await tap(tester, find.text('Grade produk'));
    await tap(tester, find.text('Tambah grade'));
    await tester.enterText(field('Nama grade'), 'Grade Uji');
    await tester.enterText(field('Kode grade'), 'u');
    await tap(tester, find.text('Simpan perubahan'));
    expect(find.textContaining('Kode U · Harga belum diatur'), findsOneWidget);

    await tap(tester, find.text('Atur harga per grade'));
    await tester.enterText(field('Grade Uji'), '1234567');
    await tap(tester, find.text('Simpan perubahan'));
    expect(
      find.text('Perubahan harga tersimpan selama sesi demo'),
      findsOneWidget,
    );
    await tap(tester, find.byTooltip('Kembali'));
    expect(find.textContaining('Rp1.234.567/kg'), findsOneWidget);

    await tap(tester, find.text('Grade Uji'));
    await select(tester, 'Status', 'Nonaktif');
    await tap(tester, find.text('Simpan perubahan'));
    await tap(tester, find.text('Atur harga per grade'));
    expect(field('Grade Uji'), findsNothing);
    await tap(tester, find.byTooltip('Kembali'));

    await tap(tester, find.text('Grade Uji'));
    await select(tester, 'Status', 'Aktif');
    await tap(tester, find.text('Simpan perubahan'));
    await tap(tester, find.text('Atur harga per grade'));
    expect(find.text('1.234.567'), findsOneWidget);
  });

  testWidgets('Alias OCR tersimpan dan hanya bisa diubah untuk field pasti', (
    tester,
  ) async {
    await settings(tester);
    await tap(tester, find.text('Formulir produksi'));
    expect(find.byTooltip('Tambah alias Brix'), findsNothing);
    await tap(tester, find.byTooltip('Tambah alias Pengirim'));
    await tester.enterText(field('Label OCR tambahan'), 'Tanggal');
    await tap(tester, find.text('Simpan perubahan'));
    expect(
      find.text('Label ini sudah digunakan pada formulir.'),
      findsOneWidget,
    );
    await tester.enterText(field('Label OCR tambahan'), 'Pemasok Uji');
    await tap(tester, find.text('Simpan perubahan'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tap(tester, find.text('Formulir produksi'));
    expect(find.text('Pemasok Uji'), findsOneWidget);
    await tap(tester, find.byTooltip('Hapus alias Pemasok Uji'));
    expect(find.text('Pemasok Uji'), findsNothing);
    await tap(tester, find.text('Nota Kedatangan Truk'));
    await tap(tester, find.text('Nota Produksi').last);
    expect(find.text('isi_kg · kg'), findsOneWidget);
  });
}
