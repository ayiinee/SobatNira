import '../kloter/demo_production.dart';
import 'demo_analytics.dart';

// A read-only join of existing demo records. No production values are inferred.
class ProductionRecap {
  ProductionRecap(
    Iterable<RecapKloter> kloter, {
    this.marginTotalOverride,
    this.batchCountOverride,
  }) : kloter = List.unmodifiable(kloter);

  factory ProductionRecap.fromRows(
    List<AnalyticsRow> rows, {
    List<AnalyticsRow> margins = const [],
    List<DemoKloter> production = const [],
  }) {
    final byCode = {for (final lot in production) lot.code: lot};
    final marginByCode = {
      for (final row in margins)
        if (readRecapNumber(row.value) != null) row.code: row.value,
    };
    final allRows = {for (final row in rows) row.code: row};
    for (final row in margins) {
      allRows.putIfAbsent(
        row.code,
        () => AnalyticsRow(row.supplier, row.code, '-', '-', day: row.day),
      );
    }
    for (final lot in production) {
      allRows.putIfAbsent(
        lot.code,
        () => AnalyticsRow(lot.supplier, lot.code, '-', '-', day: lot.date.day),
      );
    }
    final result =
        allRows.values
            .map(
              (row) => RecapKloter.fromSources(
                row,
                byCode[row.code],
                marginByCode[row.code],
              ),
            )
            .toList()
          ..sort((a, b) {
            final date = b.date.compareTo(a.date);
            return date == 0 ? a.code.compareTo(b.code) : date;
          });
    return ProductionRecap(result);
  }

  factory ProductionRecap.fromApprovedLots(Iterable<DemoKloter> lots) =>
      ProductionRecap(
        lots
            .where((lot) => lot.intake.verified || lot.milling.verified)
            .map(
              (lot) => RecapKloter(
                code: lot.code,
                supplier: lot.supplier,
                date: lot.date,
                sugar: '-',
                rendemen: '-',
                cane: lot.netWeightKg == null ? null : lot.weight,
                caneType: lot.record?['caneTypeCode'] as String?,
                vehicle: null,
                juice: lot.juiceLiters == null
                    ? null
                    : formatQuantity(lot.juiceLiters, 'L'),
                margin: null,
                batches: const [],
              ),
            ),
      );

  final String? marginTotalOverride;
  final int? batchCountOverride;
  final List<RecapKloter> kloter;
  int get batchCount =>
      batchCountOverride ??
      kloter.fold(0, (sum, lot) => sum + lot.batches.length);
  int get marginCount => kloter.where((lot) => lot.margin != null).length;
  int get sugarCount =>
      kloter.where((lot) => readRecapNumber(lot.sugar) != null).length;
  String get marginTotal =>
      marginTotalOverride ??
      (marginCount == 0
          ? '-'
          : 'Rp${formatRecapNumber(kloter.fold<num>(0, (sum, lot) => sum + (readRecapNumber(lot.margin) ?? 0)))}');
}

class RecapKloter {
  RecapKloter({
    this.id,
    required this.code,
    required this.supplier,
    required this.date,
    required this.sugar,
    required this.rendemen,
    required this.cane,
    required this.caneType,
    required this.vehicle,
    this.juice,
    required this.margin,
    required Iterable<RecapBatch> batches,
  }) : batches = List.unmodifiable(batches);

  factory RecapKloter.fromSources(
    AnalyticsRow row,
    DemoKloter? lot,
    String? margin,
  ) => RecapKloter(
    code: row.code,
    supplier: lot?.supplier ?? row.supplier,
    date: lot?.date ?? DateTime(2026, 10, row.day),
    sugar: row.value,
    rendemen: row.secondary,
    cane: lot?.weight,
    caneType: lot == null ? null : _field(lot.intake.fields, 'Jenis tebu'),
    vehicle: lot == null ? null : _field(lot.intake.fields, 'No. Kendaraan'),
    margin: margin,
    batches: lot?.batches.map(RecapBatch.fromDemo) ?? const [],
  );

  final String? id;
  final String code, supplier, sugar, rendemen;
  final DateTime date;
  final String? cane, caneType, vehicle, margin, juice;
  final List<RecapBatch> batches;
}

class RecapBatch {
  const RecapBatch({
    this.code,
    required this.number,
    required this.shift,
    required this.brix,
    required this.juice,
    required this.lime,
    required this.physical,
    required this.grade,
    required this.time,
    required this.verified,
  });

  factory RecapBatch.fromDemo(DemoBatch batch) => RecapBatch(
    number: batch.number,
    shift: _field(batch.cooking, 'Sesi'),
    brix: _field(batch.cooking, 'Brix tebu acuan'),
    juice: _field(batch.review.fields, 'Nira yang dimasak'),
    lime: _field(batch.cooking, 'Takaran gamping'),
    physical: _field(batch.review.fields, 'Hasil timbang'),
    grade: '${batch.grade} · ${batch.gradeWeight}Kg',
    time: _field(batch.review.fields, 'Jam turun'),
    verified: batch.review.verified,
  );

  final String? code;
  final int number;
  final String? shift, brix, juice, lime, physical, time;
  final String grade;
  final bool verified;

  static const columns = [
    'Batch',
    'Sesi',
    'Brix',
    'Nira',
    'Gamping',
    'Hasil fisik',
    'Grade / Berat',
    'Jam turun',
    'Status',
  ];
  List<String> get cells => [
    code ?? '$number',
    shift ?? '-',
    brix ?? '-',
    juice ?? '-',
    lime ?? '-',
    physical ?? '-',
    grade,
    time ?? '-',
    verified ? 'Tervalidasi' : 'Perlu ditinjau',
  ];
}

String? _field(List<DemoField> fields, String label) {
  for (final field in fields) {
    if (field.label == label && field.value.trim().isNotEmpty) {
      return field.display;
    }
  }
  return null;
}

num? readRecapNumber(String? value) => value == null
    ? null
    : num.tryParse(
        value
            .replaceAll(RegExp(r'[^0-9,.-]'), '')
            .replaceAll('.', '')
            .replaceAll(',', '.'),
      );

String formatRecapNumber(num value) {
  final parts = value.toString().split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );
  return parts.length > 1 && parts[1] != '0' ? '$grouped,${parts[1]}' : grouped;
}
