import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/features/laporan/demo_analytics.dart';
import 'package:sobatnira/features/laporan/production_chart.dart';
import 'package:sobatnira/features/laporan/connected_reports.dart';
import 'package:sobatnira/features/laporan/margin_chart.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';
import 'package:sobatnira/sobatnira_ui.dart';

void main() {
  test('small nonzero margins remain visible on the thousand-rupiah scale', () {
    expect(marginChartLabel(500 / 1000), '0,500');
    expect(marginChartLabel(-500 / 1000), '-0,500');
    expect(marginChartLabel(1 / 1000), '0,001');
    expect(marginChartLabel(0), '0');
    expect(marginChartLabel(475000 / 1000), '475');
  });

  testWidgets(
    'all API grades reach the legend, painted bars and touch detail',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final analytics = DemoAnalytics()..setVariant(ProductionVariant.grade);
      final api = ReviewApi('fixture');
      final reports =
          ConnectedReports(
              api,
              FactoryScope.fromJson({
                'tenantId': 'tenant',
                'tenantName': 'Audit',
                'factoryId': 'factory',
                'factoryName': 'Audit',
              }),
            )
            ..loading = false
            ..data = {
              'items': [
                {
                  'lotId': 'lot',
                  'receivedAt': '2026-10-20T00:00:00Z',
                  'caneNetKg': '100',
                  'calculation': {'finalSugarKg': '10'},
                  'batches': [
                    {
                      'grades': [
                        {'code': 'A', 'weightKg': '3'},
                      ],
                    },
                    {
                      'grades': [
                        {'code': 'X', 'weightKg': '7'},
                      ],
                    },
                  ],
                },
              ],
              'grades': [],
              'totals': {},
            };
      addTearDown(analytics.dispose);
      addTearDown(reports.dispose);
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: niraTheme(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(30),
              child: ProductionChart(
                analytics: analytics,
                reports: reports,
                onFilter: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Grade A'), findsOneWidget);
      expect(find.text('Grade X'), findsOneWidget);
      expect(find.text('Grade B'), findsNothing);
      final plot = find.byKey(const ValueKey('production-chart-plot'));
      final painted = find
          .descendant(of: plot, matching: find.byType(CustomPaint))
          .first;
      final recorder = _BarsCanvas();
      tester
          .widget<CustomPaint>(painted)
          .painter!
          .paint(recorder, tester.getSize(painted));
      expect(recorder.bars, hasLength(2));
      expect(recorder.bars.map((bar) => bar.color.toARGB32()), [
        niraOchre.toARGB32(),
        niraGreen.toARGB32(),
      ]);
      expect(
        recorder.bars.first.rect.height / recorder.bars.last.rect.height,
        closeTo(7 / 3, .00001),
      );
      final rect = tester.getRect(plot);
      await tester.tapAt(rect.topLeft + Offset(rect.width / 2, 100));
      await tester.pumpAndSettle();
      expect(find.text('A: 3 · X: 7 kg'), findsOneWidget);
      expect(find.text('Gula final: 10 kg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dropdown mengganti seri dan detail mendukung hover serta sentuhan',
    (tester) async {
      final analytics = DemoAnalytics();
      addTearDown(analytics.dispose);
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: niraTheme(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(30),
              child: ListenableBuilder(
                listenable: analytics,
                builder: (_, _) =>
                    ProductionChart(analytics: analytics, onFilter: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final title = tester.renderObject<RenderParagraph>(
        find.text('Gula final per hari (Kg)'),
      );
      final singleLineHeight = title.getMaxIntrinsicHeight(double.infinity);
      expect(title.size.height, closeTo(singleLineHeight, 0.01));
      final plot = find.byKey(const ValueKey('production-chart-plot'));
      final detail = find.byKey(const ValueKey('production-chart-detail'));
      expect(find.text('Gula final (kg)'), findsOneWidget);
      expect(detail, findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      final rect = tester.getRect(plot);
      final point = rect.topLeft + Offset(rect.width * .6, 120);
      await mouse.moveTo(point);
      await tester.pumpAndSettle();
      expect(detail, findsOneWidget);
      expect(find.textContaining('Gula final:'), findsOneWidget);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(detail, findsNothing);
      await mouse.removePointer();
      final buttonBottom = tester
          .getRect(find.byTooltip('Jenis grafik'))
          .bottom;
      await tester.tap(find.byTooltip('Jenis grafik'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('chart-option-rendemen'))).top,
        closeTo(buttonBottom, 1),
      );
      expect(
        tester.widget<Text>(find.text('Rendemen').last).style?.color,
        Colors.white,
      );
      await tester.tap(find.text('Grade').last);
      await tester.pumpAndSettle();
      expect(analytics.variant, ProductionVariant.grade);
      expect(title.size.height, closeTo(singleLineHeight, 0.01));
      expect(find.text('Grade A'), findsOneWidget);
      expect(find.text('Grade C'), findsOneWidget);
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(detail, findsOneWidget);
      expect(find.textContaining('A: '), findsOneWidget);
      await tester.tap(find.byTooltip('Jenis grafik'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chart-option-rendemen')));
      await tester.pumpAndSettle();
      expect(analytics.variant, ProductionVariant.rendemen);
      expect(title.size.height, closeTo(singleLineHeight, 0.01));
      expect(tester.takeException(), isNull);
    },
  );
}

class _BarsCanvas extends TestRecordingCanvas {
  final bars = <({Rect rect, Color color})>[];

  @override
  void drawRect(Rect rect, Paint paint) =>
      bars.add((rect: rect, color: paint.color));
}
