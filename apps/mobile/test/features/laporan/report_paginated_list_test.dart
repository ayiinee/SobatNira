import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../lib/features/laporan/report_paginated_list.dart';

void main() {
  testWidgets('pagination stays put on the partial last page', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportPaginatedList<int>(
            items: List.generate(12, (index) => index + 1),
            builder: (items) => Column(
              children: [
                for (final item in items)
                  SizedBox(height: 32, child: Text('Baris $item')),
              ],
            ),
          ),
        ),
      ),
    );

    final next = find.byTooltip('Berikutnya');
    final initialTop = tester.getTopLeft(next).dy;
    for (final page in [2, 3]) {
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('$page dari 3'), findsOneWidget);
      expect(tester.getTopLeft(next).dy, initialTop);
    }
    expect(find.text('11–12 dari 12'), findsOneWidget);
    expect(find.text('Baris 10'), findsNothing);
  });
}
