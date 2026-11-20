import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/features/kloter/demo_production.dart';
import 'package:sobatnira/features/kloter/kloter_card.dart';
import 'package:sobatnira/features/kloter/kloter_detail_page.dart';
import 'package:sobatnira/sobatnira_ui.dart';

void main() {
  testWidgets('kloter cards expose status and fit enlarged text', (
    tester,
  ) async {
    final demo = DemoProduction();
    addTearDown(demo.dispose);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final status in KloterStatus.values) {
      final lot = demo.kloter.firstWhere((lot) => lot.status == status);
      await tester.pumpWidget(
        MaterialApp(
          theme: niraTheme(),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: KloterCard(kloter: lot, onTap: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              (widget.properties.label?.contains(
                    status == KloterStatus.review
                        ? 'Perlu ditinjau'
                        : 'Tervalidasi',
                  ) ??
                  false),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'batch semantics follow validation without changing card layout',
    (tester) async {
      final demo = DemoProduction();
      final semantics = tester.ensureSemantics();
      addTearDown(demo.dispose);
      final lot = demo.kloter.firstWhere(
        (lot) => lot.status == KloterStatus.review,
      );
      await tester.binding.setSurfaceSize(const Size(393, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: niraTheme(),
          home: KloterDetailPage(kloter: lot, demo: demo, onNavigate: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp(r'^Batch \d+, Perlu ditinjau')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Batch \d+, Tervalidasi')),
        findsNWidgets(lot.batches.length - 1),
      );
      demo.verify(lot.batches.last.review);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp(r'^Batch \d+, Perlu ditinjau')),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Batch \d+, Tervalidasi')),
        findsNWidgets(lot.batches.length),
      );
      demo.reopenBatch(lot.batches.first);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp(r'^Batch \d+, Perlu ditinjau')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}
