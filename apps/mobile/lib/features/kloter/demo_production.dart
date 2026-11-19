import 'package:flutter/foundation.dart';
import 'demo_lot_fixture.dart';

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

String formatQuantity(num? number, [String unit = '']) {
  if (number == null) return 'Belum tersedia';
  final parts = number
      .toStringAsFixed(5)
      .replaceFirst(RegExp(r'0+$'), '')
      .split('.');
  final integer = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]}.',
  );
  final fraction = parts.last;
  final value = fraction.isEmpty ? integer : '$integer,$fraction';
  return unit.isEmpty ? value : '$value $unit';
}

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

  DemoProduction.empty() : kloter = [];

  static final today = DateTime(2026, 10, 25);
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
    : record = null,
      date = DateTime(2026, 10, day),
      intake = DemoReview([
        DemoField('Tanggal masuk', formatDate(DateTime(2026, 10, day))),
        DemoField(
          'Jenis tebu',
          ['Bululawang (BL)', 'PS 862', 'PS 864'][day % 3],
        ),
        DemoField('Pengirim', demoLotFor(code).supplier),
        DemoField(
          'No. Kendaraan',
          'DEMO ${day * 37 + demoLotFor(code).caneKg % 100}',
        ),
        DemoField('Operator', 'Operator Demo ${day % 3 + 1}'),
      ], verified: status == KloterStatus.done),
      milling = DemoReview([
        DemoField('Tanggal penggilingan', formatDate(DateTime(2026, 10, day))),
        DemoField('Operator', 'Operator Demo ${day % 3 + 1}'),
        DemoField('Kloter sumber', code),
      ], verified: status == KloterStatus.done),
      batches = [
        for (var number = 1; number <= demoLotFor(code).batchCount; number++)
          DemoBatch(
            number,
            verified:
                number < demoLotFor(code).batchCount ||
                status == KloterStatus.done,
            lot: demoLotFor(code),
          ),
      ];

  DemoKloter.connected({
    required this.record,
    required this.code,
    required this.date,
    required this.intake,
    required this.milling,
  }) : batches = const [];

  final Map<String, Object?>? record;
  final String code;
  final DateTime date;
  String? get id => record?['id'] as String?;
  num? get netWeightKg => _number('netWeightGrams', divisor: 1000);
  num? get brix => _number('brix');
  num? get juiceLiters => _number('juiceProducedLiters');

  num? _number(String field, {int divisor = 1}) {
    final value = num.tryParse(record?[field]?.toString() ?? '');
    return value == null ? null : value / divisor;
  }

  KloterStatus get status => record != null
      ? (record!['status'] == 'closed'
            ? KloterStatus.done
            : KloterStatus.review)
      : intake.verified && milling.verified && batchesToReview == 0
      ? KloterStatus.done
      : KloterStatus.review;
  final DemoReview intake;
  final DemoReview milling;
  final List<DemoBatch> batches;

  String get supplier =>
      (record?['supplierName'] as String?) ?? intake.fields[2].value;
  String get weight => record == null
      ? '${demoNumber(demoLotFor(code).caneKg)}Kg'
      : formatQuantity(netWeightKg, 'kg');
  int get batchesToReview =>
      batches.where((batch) => !batch.review.verified).length;
}

class DemoReview {
  DemoReview(this.fields, {required this.verified});

  final List<DemoField> fields;
  bool verified;
}

class DemoBatch {
  DemoBatch(this.number, {required bool verified, this.lot})
    : review = DemoReview([
        DemoField(
          'Nira yang dimasak',
          '${80 + ((lot?.caneKg ?? 1500) + number * 7) % 36}',
          unit: 'L',
        ),
        DemoField('Brix tebu acuan', '${15 + number % 6}', unit: ' °Bx'),
        DemoField(
          'Jam turun',
          '${8 + number + (lot?.day ?? 20) % 4}.${number.isEven ? '15' : '40'}',
        ),
        DemoField(
          'Hasil timbang',
          '${(lot?.batchWeights[number - 1] ?? 20) + 2 + number % 3}',
          unit: 'Kg',
        ),
        DemoField('Bagian kloter', '100', unit: '%'),
      ], verified: verified) {
    grade = ['A', 'B', 'C'][(number - 1) % 3];
    gradeWeight = '${lot?.batchWeights[number - 1] ?? 20}';
    cooking[0].value = formatDate(DateTime(2026, 10, lot?.day ?? 20));
    cooking[1].value = [
      'Bululawang (BL)',
      'PS 862',
      'PS 864',
    ][(lot?.day ?? 20) % 3];
    cooking[2].value = lot?.supplier ?? 'Pemasok Demo';
    cooking[3].value = cooking[0].value;
    cooking[4].value = number.isEven ? 'Sore' : 'Pagi';
    cooking[5].value = ['1/2 wadah', '1 wadah', '1 1/2 wadah'][number % 3];
  }

  final DemoLotFixture? lot;
  int get productionValue =>
      ((num.tryParse(gradeWeight.replaceAll(',', '.')) ?? 0) *
              {'A': 20000, 'B': 18000, 'C': 15000}[grade]!)
          .round();
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
