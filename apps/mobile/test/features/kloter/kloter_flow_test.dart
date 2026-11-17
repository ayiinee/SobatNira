import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/features/kloter/kloter_card.dart';
import 'package:sobatnira/features/kloter/demo_production.dart';
import 'package:sobatnira/features/kloter/kloter_list_page.dart';
import 'package:sobatnira/features/kloter/kloter_detail_widgets.dart';
import 'package:sobatnira/main.dart';
import 'package:sobatnira/sobatnira_ui.dart';

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

  Future<void> openDemo(
    WidgetTester tester, {
    Size size = const Size(393, 853),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SobatNiraApp());
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'accordion mengurutkan tanggal dan menyimpan pilihan buka tutup',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 853));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      DemoKloter? opened;
      final older = DemoKloter('LAMA', 18, KloterStatus.review, 'Pemasok A');
      final newest = DemoKloter('BARU', 20, KloterStatus.review, 'Pemasok B');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KloterListPage(
              kloter: [
                older,
                newest,
                DemoKloter('BARU-TUNTAS', 20, KloterStatus.done, 'Pemasok C'),
                DemoKloter('TENGAH', 19, KloterStatus.done, 'Pemasok D'),
              ],
              onOpenKloter: (item) => opened = item,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final headers = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.expanded != null,
      );
      expect(headers, findsNWidgets(3));
      expect(
        tester.getTopLeft(headers.at(0)).dy,
        lessThan(tester.getTopLeft(headers.at(1)).dy),
      );
      expect(find.text('BARU'), findsOneWidget);
      expect(find.text('BARU-TUNTAS'), findsOneWidget);
      expect(find.text('LAMA'), findsNothing);
      expect(find.text('TENGAH'), findsNothing);

      await tap(tester, find.text('18 Oktober 2026'));
      expect(find.text('LAMA'), findsOneWidget);
      // Multiple dates can stay open independently.
      expect(find.text('BARU'), findsOneWidget);
      await tap(tester, find.text('LAMA'));
      expect(opened, same(older));
      await tap(tester, headers.first);
      expect(find.text('BARU'), findsNothing);
      await tap(tester, find.text('Perlu Ditinjau'));
      expect(find.text('BARU'), findsNothing);
      expect(find.text('LAMA'), findsOneWidget);
      expect(find.text('19 Oktober 2026'), findsNothing);
      await tap(tester, find.text('Semua'));
      expect(find.text('BARU'), findsNothing);
      expect(find.text('LAMA'), findsOneWidget);
    },
  );

  testWidgets('pencarian, tab dan rentang bisa digabung dan dipulihkan', (
    tester,
  ) async {
    await openDemo(tester);
    expect(find.text('Tebu diterima'), findsOneWidget);
    expect(find.byType(KloterCard).evaluate().length, greaterThanOrEqualTo(3));

    await tap(tester, find.bySemanticsLabel('Kloter'));
    await tester.enterText(find.byType(TextField), ' mjt-260926-2a ');
    await tester.pumpAndSettle();
    await tap(tester, find.text('Perlu Ditinjau'));
    expect(find.byType(KloterCard), findsOneWidget);
    expect(find.text('MJT-260926-2A'), findsOneWidget);

    await tap(tester, find.byTooltip('Filter tanggal'));
    await tap(tester, find.text('Rentang tanggal'));
    await tap(tester, find.text('31'));
    expect(
      find.text('Tanggal selesai harus sama atau setelah tanggal mulai.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Terapkan'))
          .onPressed,
      isNull,
    );

    await tap(tester, find.byTooltip('Kembali ke filter tanggal'));
    await tap(tester, find.text('Rentang tanggal'));
    await tap(tester, find.text('Terapkan'));
    expect(find.byType(KloterCard), findsOneWidget);
    await tap(tester, find.text('MJT-260926-2A'));
    expect(find.text('Detail kloter'), findsOneWidget);
    await tap(tester, find.byTooltip('Kembali'));
    expect(find.text(' mjt-260926-2a '), findsOneWidget);
    expect(find.byTooltip('Filter tanggal: Rentang tanggal'), findsOneWidget);

    await tap(tester, find.byTooltip('Filter tanggal: Rentang tanggal'));
    await tap(tester, find.text('Hari ini'));
    expect(find.text('Kloter tidak ditemukan'), findsOneWidget);
    await tap(tester, find.byTooltip('Filter tanggal: Hari ini'));
    await tap(tester, find.text('Reset'));
    expect(find.text('MJT-260926-2A'), findsOneWidget);
  });

  testWidgets('edit, verifikasi dan validasi batch tersimpan selama sesi', (
    tester,
  ) async {
    await openDemo(tester);
    await tap(tester, find.text('MJT-260926-2A'));
    await tap(tester, find.text('Data tebu dan penggilingan'));
    await tap(tester, find.text('Penggilingan'));
    await tap(tester, find.text('Operator'));
    await tester.enterText(find.byType(TextFormField), 'Operator Coba');
    await tap(tester, find.text('Batal'));
    expect(find.text('Operator Demo'), findsOneWidget);

    await tap(tester, find.text('Operator'));
    await tester.enterText(find.byType(TextFormField), 'Operator Baru');
    await tap(tester, find.text('Simpan'));
    expect(find.text('Operator Baru'), findsOneWidget);
    await tap(tester, find.text('Verifikasi penggilingan'));
    expect(find.text('Penggilingan terverifikasi'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tap(tester, find.byTooltip('Kembali'));
    expect(find.text('1 Batch perlu ditinjau'), findsOneWidget);
    await tap(tester, find.text('Batch 5'));

    await tap(tester, find.text('Masak'));
    expect(find.text('Data pemasakan'), findsOneWidget);
    await tap(
      tester,
      find.descendant(of: find.byType(NiraTabs), matching: find.text('Grade')),
    );
    await tap(tester, find.bySemanticsLabel(RegExp('Edit berat grade B')));
    await tester.enterText(find.byType(TextFormField), 'bukan angka');
    await tap(tester, find.text('Simpan'));
    expect(find.text('Masukkan angka yang valid.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '24,5');
    await tap(tester, find.text('Simpan'));
    expect(find.text('24,5'), findsOneWidget);

    await tap(tester, find.text('Ringkasan'));
    await tap(tester, find.text('Validasi'));
    expect(find.text('Batch tervalidasi'), findsOneWidget);
    expect(
      tester.widget<EditableFields>(find.byType(EditableFields)).onEdit,
      isNull,
    );
    await tap(
      tester,
      find.descendant(of: find.byType(NiraTabs), matching: find.text('Grade')),
    );
    expect(find.bySemanticsLabel(RegExp('Edit berat grade')), findsNothing);
    await tap(tester, find.byTooltip('Batalkan validasi batch'));
    expect(find.bySemanticsLabel(RegExp('Edit berat grade B')), findsOneWidget);
    await tap(tester, find.text('Validasi'));
    await tap(tester, find.text('Ringkasan'));
    await tester.pump(const Duration(seconds: 5));
    await tap(tester, find.byTooltip('Kembali'));
    expect(find.text('Semua batch telah ditinjau'), findsOneWidget);
    expect(find.text('Batch 5'), findsOneWidget);
  });

  testWidgets('pembatalan validasi hanya tersedia pada batch yang dipilih', (
    tester,
  ) async {
    await openDemo(tester);
    await tap(tester, find.bySemanticsLabel('Kloter'));
    await tap(tester, find.text('MJT-260926-1A'));
    expect(find.byTooltip('Batalkan validasi batch'), findsNothing);
    expect(find.text('Kloter tervalidasi'), findsNothing);
    await tap(tester, find.text('Data tebu dan penggilingan'));
    expect(find.byTooltip('Batalkan validasi batch'), findsNothing);
    await tap(tester, find.byTooltip('Kembali'));
    await tap(tester, find.text('Batch 1'));
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(
      tester.widget<EditableFields>(find.byType(EditableFields)).onEdit,
      isNull,
    );
    await tap(tester, find.byTooltip('Batalkan validasi batch'));
    expect(
      tester.widget<EditableFields>(find.byType(EditableFields)).onEdit,
      isNotNull,
    );
    await tap(tester, find.byTooltip('Kembali'));
    expect(find.text('1 Batch perlu ditinjau'), findsOneWidget);
    await tap(tester, find.byTooltip('Kembali'));
    final card = tester.widget<KloterCard>(
      find.ancestor(
        of: find.text('MJT-260926-1A'),
        matching: find.byType(KloterCard),
      ),
    );
    expect(card.kloter.status, KloterStatus.review);
    final material = tester.widget<Material>(
      find
          .descendant(of: find.byWidget(card), matching: find.byType(Material))
          .first,
    );
    expect(material.color, niraGold);
  });

  testWidgets('pratinjau foto bisa diperbesar, dizoom dan ditutup', (
    tester,
  ) async {
    await openDemo(tester);
    await tap(tester, find.text('MJT-260926-2A'));
    await tap(tester, find.text('Data tebu dan penggilingan'));
    await tap(tester, find.byTooltip('Perbesar foto'));
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    await tap(tester, find.byTooltip('Perbesar gambar'));
    expect(
      viewer.transformationController!.value.getMaxScaleOnAxis(),
      greaterThan(1),
    );
    await tap(tester, find.text('Atur ulang'));
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
    await tap(tester, find.byTooltip('Tutup nota'));
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('konten dapat digulir ketika ukuran teks diperbesar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(
          size: Size(360, 720),
          textScaler: TextScaler.linear(2),
        ),
        child: SobatNiraApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -440));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Kloter'), findsWidgets);
  });
}
