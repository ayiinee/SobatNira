import 'package:flutter/foundation.dart';

const _months = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];

String monthName(DateTime date) => _months[date.month - 1];

String formatDate(DateTime date, {bool short = false}) {
  final month = monthName(date);
  return '${date.day} ${short ? month.substring(0, 3) : month} ${date.year}';
}

String formatMonth(DateTime date) => '${monthName(date)} ${date.year}';

enum KloterStatus { review, done }

class DemoProduction extends ChangeNotifier {
  DemoProduction()
    : kloter = [
        DemoKloter('MJT-260926-1A', 20, KloterStatus.done, 'Pemasok Contoh A'),
        DemoKloter(
          'MJT-260926-2A',
          20,
          KloterStatus.review,
          'Pemasok Contoh B',
        ),
        DemoKloter('MJT-260926-3A', 20, KloterStatus.done, 'Pemasok Contoh C'),
        DemoKloter('MJT-250926-1A', 19, KloterStatus.done, 'Pemasok Contoh A'),
        DemoKloter('MJT-250926-2A', 19, KloterStatus.done, 'Pemasok Contoh B'),
        DemoKloter(
          'MJT-240926-1A',
          18,
          KloterStatus.review,
          'Pemasok Contoh C',
        ),
        DemoKloter(
          'MJT-240926-2A',
          18,
          KloterStatus.review,
          'Pemasok Contoh A',
        ),
        DemoKloter('MJT-230926-1A', 17, KloterStatus.done, 'Pemasok Contoh B'),
        DemoKloter(
          'MJT-220926-1A',
          16,
          KloterStatus.review,
          'Pemasok Contoh D',
        ),
        DemoKloter(
          'MJT-220926-2A',
          16,
          KloterStatus.review,
          'Pemasok Contoh E',
        ),
        DemoKloter(
          'MJT-210926-1A',
          15,
          KloterStatus.review,
          'Pemasok Contoh F',
        ),
        DemoKloter(
          'MJT-200926-1A',
          14,
          KloterStatus.review,
          'Pemasok Contoh G',
        ),
        DemoKloter('MJT-190926-1A', 13, KloterStatus.done, 'Pemasok Contoh D'),
        DemoKloter('MJT-180926-1A', 12, KloterStatus.done, 'Pemasok Contoh E'),
        DemoKloter('MJT-170926-1A', 11, KloterStatus.done, 'Pemasok Contoh F'),
      ];

  static final today = DateTime(2026, 10, 29);
  final List<DemoKloter> kloter;

  void edit(DemoReview review, DemoField field, String value) {
    if (value == field.value) return;
    field.value = value;
    review.verified = false;
    notifyListeners();
  }

  void setGrade(DemoBatch batch, String grade, String weight) {
    if (batch.review.verified) return;
    if (batch.grade == grade && batch.gradeWeight == weight) return;
    batch.grade = grade;
    batch.gradeWeight = weight;
    batch.review.verified = false;
    notifyListeners();
  }

  void editBatch(DemoBatch batch, DemoField field, String value) {
    if (batch.review.verified) return;
    edit(batch.review, field, value);
  }

  void verify(DemoReview review) {
    if (review.verified) return;
    review.verified = true;
    notifyListeners();
  }

  void reopenBatch(DemoBatch batch) {
    if (!batch.review.verified) return;
    batch.review.verified = false;
    notifyListeners();
  }
}

class DemoKloter {
  DemoKloter(this.code, int day, KloterStatus status, String supplier)
    : date = DateTime(2026, 10, day),
      intake = DemoReview([
        DemoField('Tanggal masuk', formatDate(DateTime(2026, 10, day))),
        DemoField('Jenis tebu', 'Bululawang (BL)'),
        DemoField('Pengirim', supplier),
        DemoField('No. Kendaraan', 'DEMO 001'),
        DemoField('Operator', 'Operator Demo'),
      ], verified: status == KloterStatus.done),
      milling = DemoReview([
        DemoField('Tanggal penggilingan', formatDate(DateTime(2026, 10, day))),
        DemoField('Operator', 'Operator Demo'),
        DemoField('Kloter sumber', code),
      ], verified: status == KloterStatus.done),
      batches = [
        for (var number = 1; number <= 5; number++)
          DemoBatch(
            number,
            verified: number < 5 || status == KloterStatus.done,
          ),
      ];

  final String code;
  final DateTime date;
  KloterStatus get status =>
      intake.verified && milling.verified && batchesToReview == 0
      ? KloterStatus.done
      : KloterStatus.review;
  final DemoReview intake;
  final DemoReview milling;
  final List<DemoBatch> batches;

  String get supplier => intake.fields[2].value;
  String get weight => '8.200Kg';
  int get batchesToReview =>
      batches.where((batch) => !batch.review.verified).length;
}

class DemoReview {
  DemoReview(this.fields, {required this.verified});

  final List<DemoField> fields;
  bool verified;
}

class DemoBatch {
  DemoBatch(this.number, {required bool verified})
    : review = DemoReview([
        DemoField('Nira yang dimasak', '360', unit: 'L'),
        DemoField('Brix tebu acuan', 'Bululawang (BL)'),
        DemoField('Jam turun', '17.00'),
        DemoField('Hasil timbang', '30', unit: 'Kg'),
        DemoField('Bagian kloter', '100', unit: '%'),
      ], verified: verified);

  final int number;
  final DemoReview review;
  final cooking = [
    DemoField('Tanggal masak', '20 Oktober 2026'),
    DemoField('Jenis tebu', 'Bululawang (BL)'),
    DemoField('Asal nira', 'Pemasok Contoh B'),
    DemoField('Tanggal', '22 Oktober 2026'),
    DemoField('Sesi', 'Siang'),
    DemoField('Takaran gamping', '1/2 wadah'),
    DemoField('BTP lainnya', 'Tidak digunakan'),
    DemoField('Brix tebu acuan', '18,5', unit: ' °Bx'),
  ];

  static const gradePrices = {
    'A': 'Rp20.000',
    'B': 'Rp18.000',
    'C': 'Rp15.000',
  };
  String grade = 'A';
  String gradeWeight = '20';
}

class DemoField {
  DemoField(this.label, this.value, {this.unit});

  final String label;
  final String? unit;
  String value;

  String get display => '$value${unit ?? ''}';
}
