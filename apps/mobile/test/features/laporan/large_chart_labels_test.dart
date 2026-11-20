import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/features/laporan/connected_reports.dart';
import 'package:sobatnira/features/laporan/demo_analytics.dart';
import 'package:sobatnira/features/laporan/margin_chart.dart';
import 'package:sobatnira/features/laporan/production_chart.dart';
import 'package:sobatnira/features/pekerjaan/review_api.dart';
import 'package:sobatnira/sobatnira_ui.dart';

class _LabelCanvas extends TestRecordingCanvas {
  final labels = <Rect>[];
  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {
    labels.add(offset & Size(paragraph.longestLine, paragraph.height));
  }
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'large signed margins and long suppliers stay inside plot at $scale',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const amount = '-Rp1.234.567.890.123';
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
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: MarginChart(
                  onFilter: () {},
                  rows: [
                    AnalyticsRow(
                      'Pemasok dengan nama panjang sekali untuk audit',
                      'negative',
                      amount,
                      '',
                    ),
                    AnalyticsRow('Positif', 'positive', 'Rp9.876.543.210', ''),
                    AnalyticsRow('Kecil', 'small', 'Rp500', ''),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final plot = find.byKey(const ValueKey('margin-chart-plot'));
        _expectLabelsInside(tester, plot);
        final rect = tester.getRect(plot);
        await tester.tapAt(rect.topLeft + Offset(scale == 1 ? 100 : 150, 80));
        await tester.pumpAndSettle();
        expect(find.text(amount), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'large production ticks and crowded dates stay inside plot at $scale',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final api = ReviewApi('fixture');
        final analytics = DemoAnalytics();
        final reports =
            ConnectedReports(
                api,
                FactoryScope.fromJson({
                  'tenantId': 'fixture',
                  'tenantName': 'Fixture',
                  'factoryId': 'fixture',
                  'factoryName': 'Fixture',
                }),
              )
              ..loading = false
              ..data = {
                'items': [
                  for (var day = 0; day < 70; day++)
                    {
                      'lotId': '$day',
                      'receivedAt': DateTime.utc(
                        2026,
                        9,
                        day + 1,
                      ).toIso8601String(),
                      'caneNetKg': '1234567890123456',
                      'calculation': {'finalSugarKg': '1234567890123'},
                      'batches': [
                        {
                          'grades': [
                            {'code': 'A', 'weightKg': '1234567890123'},
                          ],
                        },
                      ],
                    },
                ],
                'grades': [],
                'totals': {},
              };
        addTearDown(api.close);
        addTearDown(analytics.dispose);
        addTearDown(reports.dispose);
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
              body: Padding(
                padding: const EdgeInsets.all(16),
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
        _expectLabelsInside(
          tester,
          find.byKey(const ValueKey('production-chart-plot')),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

void _expectLabelsInside(WidgetTester tester, Finder plot) {
  final painted = find
      .descendant(of: plot, matching: find.byType(CustomPaint))
      .first;
  final size = tester.getSize(painted);
  final canvas = _LabelCanvas();
  tester.widget<CustomPaint>(painted).painter!.paint(canvas, size);
  expect(canvas.labels, isNotEmpty);
  for (final bounds in canvas.labels) {
    expect(bounds.left, greaterThanOrEqualTo(-.01));
    expect(bounds.top, greaterThanOrEqualTo(-.01));
    expect(bounds.right, lessThanOrEqualTo(size.width + .01));
    expect(bounds.bottom, lessThanOrEqualTo(size.height + .01));
  }
}
