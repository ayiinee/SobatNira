import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
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
                builder: (_, _) => ProductionChart(analytics: analytics),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
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
      await tester.tap(find.byTooltip('Jenis grafik'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('Rendemen').last).style?.color,
        Colors.white,
      );
      await tester.tap(find.text('Grade').last);
      await tester.pumpAndSettle();
      expect(analytics.variant, ProductionVariant.grade);
      expect(find.text('Grade A'), findsOneWidget);
      expect(find.text('Grade C'), findsOneWidget);
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(detail, findsOneWidget);
      expect(find.textContaining('A: '), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
