import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/features/laporan/demo_analytics.dart';
import 'package:sobatnira/features/laporan/production_chart.dart';
import 'package:sobatnira/sobatnira_ui.dart';

void main() {
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
