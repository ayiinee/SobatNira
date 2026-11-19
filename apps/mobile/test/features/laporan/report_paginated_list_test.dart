import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/features/laporan/report_paginated_list.dart';
import 'package:sobatnira/sobatnira_ui.dart';

void main() {
  testWidgets('API pagination holds the footer while loading', (tester) async {
    final height = NiraPageHeight();
    final lastPage = Completer<int>();
    var page = 1;
    var request = Future.value(5);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => NiraPagedFutureBuilder<int>(
              future: request,
              page: page,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator();
                }
                return ListView(
                  children: [
                    NiraPageBody(
                      height: height,
                      firstPage: page == 1,
                      child: SizedBox(height: snapshot.requireData * 120.0),
                    ),
                    NiraPagination(
                      page: page,
                      pageCount: 2,
                      onNext: page == 1
                          ? () => setState(() {
                              page = 2;
                              request = lastPage.future;
                            })
                          : null,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pumpAndSettle();
    final next = find.byTooltip('Berikutnya');
    await tester.ensureVisible(next);
    final initialTop = tester.getTopLeft(find.byType(NiraPagination)).dy;
    await tester.tap(next);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.getTopLeft(find.byType(NiraPagination)).dy, initialTop);
    lastPage.complete(1);
    await tester.pumpAndSettle();
    expect(find.text('2 dari 2'), findsOneWidget);
    expect(tester.getTopLeft(find.byType(NiraPagination)).dy, initialTop);
    expect(next, findsNothing);
  });

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
    final initialTop = tester.getTopLeft(find.byType(NiraPagination)).dy;
    for (final page in [2, 3]) {
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('$page dari 3'), findsOneWidget);
      expect(tester.getTopLeft(find.byType(NiraPagination)).dy, initialTop);
    }
    expect(find.text('11–12 dari 12'), findsNothing);
    expect(find.text('Baris 10'), findsNothing);
  });
}
