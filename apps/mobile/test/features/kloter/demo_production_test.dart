import 'package:flutter_test/flutter_test.dart';
import 'package:sobatnira/features/kloter/demo_production.dart';

void main() {
  test('validated values stay locked until validation is cancelled', () {
    final demo = DemoProduction();
    addTearDown(demo.dispose);
    final lot = demo.kloter.first;
    final batch = lot.batches.first;
    final field = batch.cooking.first;
    final original = field.value;
    demo.editBatch(batch, field, 'Revisi');
    demo.setGrade(batch, 'B', '25');
    expect(field.value, original);
    expect(batch.grade, 'A');
    expect(lot.status, KloterStatus.done);

    demo.reopenBatch(batch);
    expect(lot.status, KloterStatus.review);
    demo.editBatch(batch, field, 'Revisi');
    demo.setGrade(batch, 'B', '25');
    expect(field.value, 'Revisi');
    expect(batch.grade, 'B');
    demo.verify(batch.review);
    expect(lot.status, KloterStatus.done);

    demo.reopenBatch(batch);
    expect(lot.intake.verified, isTrue);
    expect(lot.milling.verified, isTrue);
    expect(lot.batchesToReview, 1);
    expect(lot.batches.skip(1).every((other) => other.review.verified), isTrue);
    expect(lot.status, KloterStatus.review);
    // Cancelling validation preserves the recorded values for correction.
    expect(field.value, 'Revisi');
    expect(batch.gradeWeight, '25');
  });
}
