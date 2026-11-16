import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/sobatnira_ui.dart';

void main() {
  testWidgets('tab mendukung ukuran intrinsik pada SliverFillRemaining', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    children: [
                      NiraTabs(
                        labels: const ['Tinjau', 'Tuntas'],
                        selected: selected,
                        wideIndicator: true,
                        onSelected: (value) => setState(() => selected = value),
                      ),
                      const Text('Konten Beranda'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Tuntas'));
    await tester.pump(const Duration(milliseconds: 160));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(find.text('Konten Beranda'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
