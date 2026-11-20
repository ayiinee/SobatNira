import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/widgets/nira_loading.dart';

void main() {
  testWidgets('loader stays centered until work resolves', (tester) async {
    final semantics = tester.ensureSemantics();
    Widget screen({required bool busy, bool reducedMotion = false}) =>
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reducedMotion),
            child: Scaffold(
              body: NiraLoading(
                busy: busy,
                label: 'Memuat kloter…',
                child: const Text('Kloter siap'),
              ),
            ),
          ),
        );

    await tester.pumpWidget(screen(busy: true));
    await tester.pump(const Duration(seconds: 7));
    expect(find.bySemanticsLabel('Memuat kloter…'), findsOneWidget);
    expect(find.text('Kloter siap'), findsNothing);
    final indicator = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == 'Memuat kloter…',
    );
    expect(
      tester.getCenter(indicator),
      tester.getCenter(find.byType(Scaffold)),
    );

    await tester.pumpWidget(screen(busy: false));
    expect(find.text('Memuat kloter…'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Kloter siap'), findsOneWidget);

    await tester.pumpWidget(screen(busy: true, reducedMotion: true));
    await tester.pumpWidget(screen(busy: false, reducedMotion: true));
    expect(find.text('Kloter siap'), findsOneWidget);
    semantics.dispose();
  });
}
