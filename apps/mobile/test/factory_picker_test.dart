import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/features/beranda/factory_picker.dart';

void main() {
  testWidgets('pilihan pabrik bisa dihover, dipilih, dan muncul teratas', (
    tester,
  ) async {
    var factory = 'Pabrik A';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Align(
              alignment: Alignment.topRight,
              child: FactoryPicker(
                value: factory,
                onChanged: (value) => setState(() => factory = value),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Pilih pabrik'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Pabrik B')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Pabrik B'));
    await tester.pumpAndSettle();
    expect(factory, 'Pabrik B');

    await tester.tap(find.byTooltip('Pilih pabrik'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Pabrik B')).dy,
      lessThan(tester.getTopLeft(find.text('Pabrik A')).dy),
    );
    await tester.tapAt(const Offset(10, 400));
    await tester.pumpAndSettle();
    expect(find.text('Pabrik B'), findsNothing);
    expect(factory, 'Pabrik B');
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });
}
