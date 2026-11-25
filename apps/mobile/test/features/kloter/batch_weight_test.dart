import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/features/kloter/batch_draft_page.dart';

void main() {
  test('grade differences retain microgram precision and signed shrinkage', () {
    final total = productionWeightUnits('0,1')! + productionWeightUnits('0.2')!;
    expect(productionWeight(total), '0.3');
    expect(productionWeight(total - productionWeightUnits('0.300001')!), '-0.000001');
    expect(productionWeightUnits('1.0000001'), isNull);
    expect(productionWeightUnits('1e3'), isNull);
  });
}
