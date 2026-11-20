import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/features/beranda/beranda_page.dart';
import 'package:sobatnira/features/kloter/demo_production.dart';
import 'package:sobatnira/sobatnira_ui.dart';

void main() {
  for (final size in [const Size(430, 950), const Size(320, 500)]) {
    testWidgets('review and completed panels explain empty filters at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final demo = DemoProduction();
      addTearDown(demo.dispose);
      for (final status in KloterStatus.values) {
        final lots = demo.kloter.where((lot) => lot.status == status).toList();
        await tester.pumpWidget(
          MaterialApp(
            theme: niraTheme(),
            home: Scaffold(
              body: BerandaPage(kloter: lots, onOpenKloter: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final normalScroll = find.descendant(
          of: find.byKey(const ValueKey('beranda-kloter-list')),
          matching: find.byType(Scrollable),
        );
        final compactScroll = find.descendant(
          of: find.byKey(const PageStorageKey('beranda-compact-scroll')),
          matching: find.byType(Scrollable),
        );
        if (status == KloterStatus.review) {
          await tester.scrollUntilVisible(
            find.text('Tuntas').hitTestable(),
            100,
            scrollable:
                (normalScroll.evaluate().isEmpty ? compactScroll : normalScroll)
                    .first,
          );
          await tester.tap(find.text('Tuntas'));
          await tester.pumpAndSettle();
        }
        final message = find.text(
          status == KloterStatus.done
              ? 'Tidak ada kloter yang perlu ditinjau.'
              : 'Belum ada kloter tuntas.',
        );
        await tester.scrollUntilVisible(
          message,
          100,
          scrollable:
              (normalScroll.evaluate().isEmpty ? compactScroll : normalScroll)
                  .first,
        );
        expect(message.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  testWidgets('factory with no lots has a message and retains loading status', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: niraTheme(),
        home: Scaffold(
          body: BerandaPage(kloter: const [], onOpenKloter: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Belum ada kloter di pabrik ini.'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        theme: niraTheme(),
        home: Scaffold(
          body: BerandaPage(
            kloter: const [],
            onOpenKloter: (_) {},
            statusMessage: const Text('Memuat data pabrik'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Memuat data pabrik'), findsOneWidget);
    expect(find.text('Belum ada kloter di pabrik ini.'), findsNothing);
  });
}
