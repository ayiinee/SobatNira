import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/features/laporan/demo_analytics.dart';
import 'package:sobatnira/features/laporan/laporan_page.dart';
import 'package:sobatnira/features/laporan/report_paginated_list.dart';
import 'package:sobatnira/sobatnira_ui.dart';

void main() {
  testWidgets(
    'Rendemen and Margin paginate five rows and reset after filtering',
    (tester) async {
      final analytics = DemoAnalytics();
      addTearDown(analytics.dispose);
      await tester.binding.setSurfaceSize(const Size(393, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: niraTheme(),
          home: Scaffold(
            body: LaporanPage(analytics: analytics, onOpenDetail: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> next() async {
        await tester.ensureVisible(find.byTooltip('Berikutnya'));
        await tester.tap(find.byTooltip('Berikutnya'));
        await tester.pumpAndSettle();
      }

      expect(find.text('Sugeng'), findsOneWidget);
      expect(find.text('Masud'), findsOneWidget);
      expect(find.text('Salim'), findsNothing);
      expect(find.text('1–5 dari 12'), findsOneWidget);
      expect(find.text('1 dari 3'), findsOneWidget);
      await next();
      expect(find.text('Sugeng'), findsNothing);
      expect(find.text('Salim'), findsOneWidget);
      expect(find.text('Wahyu'), findsOneWidget);
      await next();
      expect(find.text('Budi'), findsOneWidget);
      expect(find.text('Rini'), findsOneWidget);
      expect(find.text('11–12 dari 12'), findsOneWidget);
      expect(find.text('3 dari 3'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Berikutnya',
              ),
            )
            .onPressed,
        isNull,
      );

      analytics.setQuery('Sugeng');
      await tester.pumpAndSettle();
      expect(find.text('Sugeng'), findsOneWidget);
      expect(find.byTooltip('Berikutnya'), findsNothing);
      analytics.setQuery('tidak-ada');
      await tester.pumpAndSettle();
      expect(find.text('Data tidak ditemukan'), findsOneWidget);

      analytics.setQuery('');
      analytics.setTab(ReportTab.margin);
      await tester.pumpAndSettle();
      expect(find.text('1–5 dari 10'), findsOneWidget);
      await next();
      expect(find.text('Hadi'), findsOneWidget);
      expect(find.text('Rini'), findsOneWidget);
      expect(find.text('Sugeng'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pagination handles shrinking data and narrow large-text layouts',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Widget page(int count) => MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: ReportPaginatedList<int>(
              items: List.generate(count, (i) => i),
              builder: (rows) =>
                  Column(children: [for (final row in rows) Text('Item $row')]),
            ),
          ),
        ),
      );
      await tester.pumpWidget(page(12));
      await tester.tap(find.byTooltip('Berikutnya'));
      await tester.pump();
      await tester.tap(find.byTooltip('Berikutnya'));
      await tester.pump();
      expect(find.text('Item 10'), findsOneWidget);
      await tester.pumpWidget(page(2));
      expect(find.text('Item 0'), findsOneWidget);
      expect(find.text('Item 1'), findsOneWidget);
      expect(find.byTooltip('Berikutnya'), findsNothing);
      await tester.pumpWidget(page(0));
      expect(find.textContaining('Item '), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
