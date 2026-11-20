import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/sobatnira_ui.dart';
import 'package:sobatnira/widgets/adaptive_value.dart';
import 'package:sobatnira/widgets/summary_card.dart';
import 'package:sobatnira/features/kloter/kloter_detail_widgets.dart';
import 'package:sobatnira/features/kloter/demo_production.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/sobatnira/fonts/Inter-$weight.ttf'));
    }
    await font.load();
  });

  test(
    'abbreviation preserves signs and units without converting exact decimals',
    () {
      expect(compactDisplayValue('-Rp1.234.567.890.123'), '-Rp1,23 triliun');
      expect(compactDisplayValue('1.234.567,125 kg'), '1,23 juta kg');
      expect(
        compactDisplayValue('Rp9.007.199.254.740.993.123'),
        'Rp9007199,25 triliun',
      );
      expect(scientificDisplayValue('Rp9.007.199.254.740.993.123'), 'Rp9e18');
      expect(compactDisplayValue('0,000001 L'), '0,000001 L');
      expect(compactDisplayValue('—'), '—');
      expect(compactDisplayValue('Belum tersedia'), 'Belum tersedia');
    },
  );

  for (final width in [320.0, 360.0, 430.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        'amount changes preserve card sizes at $width and text $scale',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 1200));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          Map<String, Size>? baseline;
          for (final value in [
            '1.250 kg',
            '1.234.567,125 kg',
            '9.007.199.254.740.993,123456 kg',
          ]) {
            await tester.pumpWidget(
              MaterialApp(
                theme: niraTheme(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(30),
                      child: Column(
                        children: [
                          NiraSummaryPair(
                            first: NiraSummaryCard(
                              'Gula final',
                              value,
                              key: const ValueKey('first'),
                            ),
                            second: const NiraSummaryCard(
                              'Tebu diterima',
                              '1.250 kg',
                              key: ValueKey('second'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          NiraSummaryPair(
                            first: NiraSummaryCard(
                              'Nilai produksi',
                              'Rp${value.replaceAll(' kg', '')}',
                              compactValue: true,
                              key: const ValueKey('money'),
                            ),
                            second: const NiraSummaryCard(
                              'Total biaya',
                              'Rp125.000',
                              compactValue: true,
                              key: ValueKey('cost'),
                            ),
                          ),
                          DetailMetrics([
                            ('Tebu', value),
                            ('Brix', '18,5 °Bx'),
                            ('Nira', '481 L'),
                          ], key: const ValueKey('metrics')),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final measured = {
              for (final key in ['first', 'second', 'money', 'cost', 'metrics'])
                key: tester.getSize(find.byKey(ValueKey(key))),
            };
            expect(measured['first']!.height, measured['second']!.height);
            expect(measured['money']!.height, measured['cost']!.height);
            baseline ??= measured;
            expect(measured, baseline);
            for (final element
                in find
                    .descendant(
                      of: find.byType(NiraValue),
                      matching: find.byType(Text),
                    )
                    .evaluate()) {
              final paragraph = element.findRenderObject()! as RenderParagraph;
              expect(paragraph.maxLines, 1);
              final text = element.widget as Text;
              expect(text.style!.fontSize, anyOf(20, 24));
            }
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }

  testWidgets('a shortened value opens the exact selectable backend string', (
    tester,
  ) async {
    const value = '-Rp9.007.199.254.740.993.123,456789';
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: niraTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 130,
              child: NiraValue(
                value,
                label: 'Margin Produksi',
                style: niraText(24),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Margin Produksi: $value'), findsOneWidget);
    await tester.tap(find.byType(NiraValue));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      value,
    );
    expect(find.text('Margin Produksi'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets(
    'detail decimals stay complete at readable size and can be scrolled',
    (tester) async {
      const value = '83,500125123456789 L';
      await tester.pumpWidget(
        MaterialApp(
          theme: niraTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 85,
                child: NiraValue(value, abbreviate: false, style: niraText(14)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(value), findsOneWidget);
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      await tester.drag(find.byType(NiraValue), const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long editable values still open the existing editor', (
    tester,
  ) async {
    DemoField? edited;
    final field = DemoField(
      'Nira yang dimasak',
      '83.500,125123456789123456789 L',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: niraTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: EditableFields(
              fields: [field],
              onEdit: (value) => edited = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(field.value));
    await tester.pumpAndSettle();
    expect(edited, same(field));
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
