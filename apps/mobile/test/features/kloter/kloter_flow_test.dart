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

  testWidgets('pagination menampilkan maksimal 10 tanggal per halaman', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KloterListPage(
            kloter: [
              for (var day = 10; day <= 20; day++)
                DemoKloter(
                  'KLOTER-$day',
                  day,
                  KloterStatus.review,
                  'Pemasok A',
                ),
              DemoKloter('TAMBAHAN-11', 11, KloterStatus.review, 'Pemasok B'),
            ],
            onOpenKloter: (_) {},
          ),
        ),
      ),
    );
    final dateHeaders = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.expanded != null,
    );
    expect(dateHeaders, findsNWidgets(10));
    expect(find.text('1 dari 2'), findsOneWidget);
    expect(find.byTooltip('Sebelumnya'), findsNothing);
    expect(find.text('10 Oktober 2026'), findsNothing);
    await tap(tester, find.text('11 Oktober 2026'));
    expect(find.text('KLOTER-11'), findsOneWidget);
    expect(find.text('TAMBAHAN-11'), findsOneWidget);

    await tap(tester, find.byTooltip('Berikutnya'));
    expect(find.text('2 dari 2'), findsOneWidget);
    expect(find.byTooltip('Berikutnya'), findsNothing);
    expect(dateHeaders, findsOneWidget);
    expect(find.text('11 Oktober 2026'), findsNothing);
    expect(find.text('KLOTER-10'), findsOneWidget);
    await tap(tester, find.byTooltip('Sebelumnya'));
    expect(dateHeaders, findsNWidgets(10));

    await tap(tester, find.byTooltip('Berikutnya'));
    await tap(tester, find.byTooltip('Filter tanggal'));
    await tap(tester, find.text('Minggu ini'));
    expect(find.byType(NiraPagination), findsNothing);
    expect(find.text('KLOTER-20'), findsOneWidget);
    expect(find.text('10 Oktober 2026'), findsNothing);

    await tester.enterText(find.byType(TextField), 'KLOTER-20');
    await tester.pumpAndSettle();
    expect(find.byType(KloterCard), findsOneWidget);
    expect(find.byType(NiraPagination), findsNothing);
    await tap(tester, find.text('Tuntas'));
    expect(find.text('Kloter tidak ditemukan'), findsOneWidget);
    expect(find.byType(NiraPagination), findsNothing);
  });

  testWidgets('pencarian, tab dan rentang bisa digabung dan dipulihkan', (
    tester,
  ) async {
    await openDemo(tester);
    expect(find.text('Tebu diterima'), findsOneWidget);
    // Status labels change how many cards fit in the initial viewport.
    expect(find.byType(KloterCard).evaluate().length, greaterThanOrEqualTo(1));

    await tap(tester, find.bySemanticsLabel('Kloter'));
    final next = find.byTooltip('Berikutnya');
    expect(next.hitTestable(), findsNothing);
    await tester.scrollUntilVisible(
      next,
      160,
      scrollable: find.descendant(
        of: find.byKey(const PageStorageKey('kloter-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(next.hitTestable(), findsOneWidget);
    expect(find.text('1 dari 2'), findsOneWidget);
    await tap(tester, next);
    expect(find.text('2 dari 2'), findsOneWidget);
    expect(find.text('MJT-160926-1A'), findsOneWidget);
    await tap(tester, find.byTooltip('Sebelumnya'));

    void expectSearchAligned() {
      final search = InputDecorator.containerOf(
        tester.element(find.byType(EditableText)),
      )!;
      final filter = tester.getRect(find.byTooltip('Filter tanggal'));
      expect(search.localToGlobal(Offset.zero).dy, filter.top);
      expect(search.size.height, filter.height);
    }

    expectSearchAligned();
    await tester.enterText(find.byType(TextField), ' mjt-260926-2a ');
    await tester.pumpAndSettle();
    expectSearchAligned();
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

  testWidgets('angka detail mengikuti kloter dan perubahan batch demo', (
    tester,
  ) async {
    await openDemo(tester, size: const Size(393, 1000));
    await tap(tester, find.bySemanticsLabel('Kloter'));
    await tester.enterText(find.byType(TextField), 'mjt-220926');
    await tester.pumpAndSettle();

    expect(find.text('1.435Kg'), findsOneWidget);
    await tap(tester, find.text('MJT-220926-1A'));
    expect(find.text('1.435Kg'), findsOneWidget);
    expect(find.text('19,4 °Bx'), findsOneWidget);
    expect(find.text('267 L'), findsOneWidget);
    expect(find.text('82L'), findsOneWidget);
    expect(find.text('28Kg'), findsOneWidget);
    expect(find.text('96L'), findsOneWidget);
    expect(find.text('31Kg'), findsOneWidget);

    await tap(tester, find.text('Data tebu dan penggilingan'));
    expect(find.text('1.435Kg'), findsOneWidget);
    expect(find.text('19,4 °Bx'), findsOneWidget);
    await tap(tester, find.text('Penggilingan'));
    expect(find.text('267 L'), findsOneWidget);
    await tap(tester, find.byTooltip('Kembali'));

    await tap(tester, find.text('Batch 3'));
    expect(find.text('96L'), findsOneWidget);
    expect(find.text('31Kg'), findsOneWidget);
    await tap(tester, find.text('Nira yang dimasak'));
    await tester.enterText(find.byType(TextFormField), '101,5');
    await tap(tester, find.text('Simpan'));
    await tap(tester, find.byTooltip('Kembali'));
    expect(find.text('101,5L'), findsOneWidget);
    expect(find.text('272,5 L'), findsOneWidget);

    await tap(tester, find.byTooltip('Kembali'));
    await tap(tester, find.text('MJT-220926-2A'));
    expect(find.text('1.580Kg'), findsOneWidget);
    expect(find.text('567 L'), findsOneWidget);
    expect(find.text('83L'), findsOneWidget);
    expect(find.text('101,5L'), findsNothing);
  });

  testWidgets('edit, verifikasi dan validasi batch tersimpan selama sesi', (
    tester,
  ) async {
    const statusBarHeight = 44.0;
    tester.view.viewPadding = FakeViewPadding(
      top: statusBarHeight * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetViewPadding);

    Rect reviewButtonRect(String label) => tester.getRect(
      find.descendant(
        of: find.widgetWithText(NiraButton, label),
        matching: find.byType(Material),
      ),
    );

    await openDemo(tester);
    await tap(tester, find.text('MJT-260926-2A'));
    await tap(tester, find.text('Data tebu dan penggilingan'));
    final intakeButton = reviewButtonRect('Verifikasi tebu masuk');
    await tap(tester, find.text('Penggilingan'));
    expect(reviewButtonRect('Verifikasi penggilingan'), intakeButton);
    await tap(tester, find.text('Operator'));
    await tester.enterText(find.byType(TextFormField), 'Operator Coba');
    await tap(tester, find.text('Batal'));
    expect(find.text('Operator Demo 3'), findsOneWidget);

    await tap(tester, find.text('Operator'));
    await tester.enterText(find.byType(TextFormField), 'Operator Baru');
    await tap(tester, find.text('Simpan'));
    expect(find.text('Operator Baru'), findsOneWidget);
    await tap(tester, find.text('Verifikasi penggilingan'));
    expect(find.text('Penggilingan terverifikasi'), findsOneWidget);
    final reviewedMillingButton = reviewButtonRect(
      'Penggilingan terverifikasi',
    );
    await tester.pump(const Duration(seconds: 5));
    await tap(tester, find.byTooltip('Kembali'));
    expect(find.text('1 Batch perlu ditinjau'), findsOneWidget);
    await tap(tester, find.text('Batch 3'));

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
    expect(reviewButtonRect('Validasi'), intakeButton);
    await tap(tester, find.text('Validasi'));
    expect(find.text('Validasi Batch 3?'), findsOneWidget);
    final cancelAction = find.widgetWithText(OutlinedButton, 'Batal');
    final confirmAction = find.widgetWithText(FilledButton, 'Konfirmasi');
    expect(
      tester.getSize(cancelAction).width,
      tester.getSize(confirmAction).width,
    );
    final cancelStyle = tester.widget<OutlinedButton>(cancelAction).style!;
    expect(cancelStyle.foregroundColor!.resolve({}), niraGreen);
    expect(cancelStyle.side!.resolve({})!.color, niraGreen);
    final validatedNotice = find.text('Batch 3 berhasil divalidasi');
    await tap(tester, find.text('Batal'));
    expect(find.text('Batch tervalidasi'), findsNothing);
    expect(validatedNotice, findsNothing);
    expect(
      tester.widget<EditableFields>(find.byType(EditableFields)).onEdit,
      isNotNull,
    );
    await tap(tester, find.text('Validasi'));
    await tap(tester, find.text('Konfirmasi'));
    expect(find.text('Batch tervalidasi'), findsOneWidget);
    expect(validatedNotice, findsOneWidget);
    expect(find.text('Kloter MJT-260926-2A'), findsOneWidget);
    final noticeSurface = find
        .ancestor(of: validatedNotice, matching: find.byType(Material))
        .first;
    final noticeBounds = tester.getRect(noticeSurface);
    final contentBounds = tester.getRect(find.byType(EditableFields));
    expect(noticeBounds.left, contentBounds.left);
    expect(noticeBounds.right, contentBounds.right);
    expect(noticeBounds.top, statusBarHeight);
    expect(tester.widget<Material>(noticeSurface).color, Colors.white);
    final validationButton = reviewButtonRect('Batch tervalidasi');
    expect(validationButton.top, reviewedMillingButton.top);
    expect(validationButton.bottom, reviewedMillingButton.bottom);
    final cancelButton = tester.getRect(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is IconButton &&
              widget.tooltip == 'Batalkan validasi batch',
        ),
        matching: find.byType(Material),
      ),
    );
    expect(validationButton.top, cancelButton.top);
    expect(validationButton.bottom, cancelButton.bottom);
    expect(
      tester.widget<EditableFields>(find.byType(EditableFields)).onEdit,
      isNull,
    );
    final noticeTop = tester.getTopLeft(validatedNotice).dy;
    await tester.pump(const Duration(seconds: 6));
    expect(tester.getTopLeft(validatedNotice).dy, noticeTop);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 160));
    expect(tester.getTopLeft(validatedNotice).dy, lessThan(noticeTop));
    await tester.pumpAndSettle();
    expect(validatedNotice, findsNothing);
    await tap(
      tester,
      find.descendant(of: find.byType(NiraTabs), matching: find.text('Grade')),
    );
    expect(find.bySemanticsLabel(RegExp('Edit berat grade')), findsNothing);
    await tap(tester, find.byTooltip('Batalkan validasi batch'));
    expect(find.text('Batalkan validasi Batch 3?'), findsOneWidget);
    expect(
      tester.getSize(cancelAction).width,
      tester.getSize(confirmAction).width,
    );
    await tap(tester, find.text('Batal'));
    expect(find.text('Batch tervalidasi'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Edit berat grade')), findsNothing);
    await tap(tester, find.byTooltip('Batalkan validasi batch'));
    await tap(tester, find.text('Konfirmasi'));
    expect(find.bySemanticsLabel(RegExp('Edit berat grade B')), findsOneWidget);
    final reopenedNotice = find.text('Validasi Batch 3 dibatalkan');
    expect(reopenedNotice, findsOneWidget);
    expect(find.text('Kloter MJT-260926-2A'), findsOneWidget);
    final reopenedBounds = tester.getRect(
      find.ancestor(of: reopenedNotice, matching: find.byType(Material)).first,
    );
    expect(reopenedBounds.left, contentBounds.left);
    expect(reopenedBounds.right, contentBounds.right);
    await tap(tester, find.text('Validasi'));
    await tester.tap(find.text('Konfirmasi'));
    await tester.pump();
    expect(validatedNotice, findsNothing);
    for (
      var frame = 0;
      frame < 30 && validatedNotice.evaluate().isEmpty;
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(AlertDialog), findsNothing);
    expect(validatedNotice, findsOneWidget);
    expect(reopenedNotice, findsNothing);
    final enteringTop = tester.getTopLeft(noticeSurface).dy;
    expect(enteringTop, lessThan(statusBarHeight));
    await tester.pump(const Duration(milliseconds: 200));
    final midwayTop = tester.getTopLeft(noticeSurface).dy;
    expect(midwayTop, greaterThan(enteringTop));
    expect(midwayTop, lessThan(statusBarHeight));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(noticeSurface).dy, statusBarHeight);
    await tap(tester, find.text('Ringkasan'));
    await tester.pump(const Duration(seconds: 5));
    await tap(tester, find.byTooltip('Kembali'));
    expect(find.text('Semua batch telah ditinjau'), findsOneWidget);
    expect(find.text('Batch 3'), findsOneWidget);
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
    await tap(tester, find.text('Konfirmasi'));
    expect(
      tester.widget<EditableFields>(find.byType(EditableFields)).onEdit,
      isNotNull,
    );
    await tap(tester, find.byTooltip('Kembali'));
    expect(find.text('1 Batch perlu ditinjau'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byTooltip('Kembali'),
      -300,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
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
    expect(material.color, const Color(0xFFCFA331));
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
    expect(find.bySemanticsLabel('Kloter').hitTestable(), findsOneWidget);
  });
}
