import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/features/beranda/beranda_page.dart';
import 'package:sobatnira/features/kloter/kloter_list_page.dart';
import 'package:sobatnira/features/laporan/laporan_page.dart';
import 'package:sobatnira/features/pengaturan/pengaturan_page.dart';
import 'package:sobatnira/main.dart';

void main() {
  testWidgets('tab dimuat saat dibuka dan mempertahankan isian saat kembali', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SobatNiraApp());
    await tester.pumpAndSettle();
    expect(find.byType(BerandaPage), findsOneWidget);
    expect(find.byType(KloterListPage, skipOffstage: false), findsNothing);
    expect(find.byType(LaporanPage, skipOffstage: false), findsNothing);
    expect(find.byType(PengaturanPage, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.bySemanticsLabel('Kloter'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'MJT-260926-2A');
    await tester.pumpAndSettle();
    expect(find.byType(KloterListPage), findsOneWidget);
    expect(find.byType(LaporanPage, skipOffstage: false), findsNothing);

    await tester.tap(find.bySemanticsLabel('Beranda'));
    await tester.pumpAndSettle();
    expect(find.byType(BerandaPage), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Kloter'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'MJT-260926-2A',
    );
    expect(tester.takeException(), isNull);
  });
}
