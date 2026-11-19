import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/features/kloter/demo_lot_fixture.dart';
import 'package:sobatnira/features/kloter/demo_production.dart';

void main() {
  test('export fixture Flutter untuk seeder database', () {
    const output = String.fromEnvironment('DEMO_FIXTURE_OUTPUT');
    expect(output, isNotEmpty);
    final demo = DemoProduction();
    addTearDown(demo.dispose);
    final byCode = {for (final lot in demo.kloter) lot.code: lot};
    final prices = {
      for (final entry in DemoBatch.gradePrices.entries)
        entry.key: int.parse(entry.value.replaceAll(RegExp(r'[^0-9]'), '')),
    };

    final rows = demoLotFixtures.map((fixture) {
      // Some lots exist only in the analytics fixture.
      final lot =
          byCode[fixture.code] ??
          DemoKloter(
            fixture.code,
            fixture.day,
            KloterStatus.review,
            fixture.supplier,
          );
      final batches = lot.batches.map((batch) {
        final time = batch.review.fields.firstWhere(
          (field) => field.label == 'Jam turun',
        );
        return {
          'number': batch.number,
          'wok': (batch.number - 1) % 3 + 1,
          'time': time.value.replaceFirst('.', ':').padLeft(5, '0'),
          'juiceLiters': int.parse(batch.juice.value),
          'physicalKg': int.parse(batch.physicalWeight.value),
          'grade': batch.grade,
          'gradeKg': int.parse(batch.gradeWeight),
          'priceRupiah': prices[batch.grade],
          'approved': batch.review.verified,
        };
      }).toList();
      return {
        'code': lot.code,
        'supplier': lot.supplier,
        'date': lot.date.toIso8601String().substring(0, 10),
        'caneKg': fixture.caneKg,
        'brix': fixture.brix.toString(),
        'caneType': ['BL', 'PS862', 'PS864'][fixture.day % 3],
        'closed': lot.status == KloterStatus.done,
        'targetMarginRupiah': fixture.marginRupiah,
        'fullSugarKg': fixture.sugarKg,
        'batches': batches,
      };
    }).toList();
    final file = File(output);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(rows)}\n',
    );
  });
}
