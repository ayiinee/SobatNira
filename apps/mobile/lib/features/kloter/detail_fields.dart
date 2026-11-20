import 'demo_production.dart';

const intakeDetailLabels = [
  'Tanggal masuk',
  'Jenis tebu',
  'Pengirim',
  'No. Kendaraan',
  'Operator',
];
const millingDetailLabels = [
  'Tanggal penggilingan',
  'Operator',
  'Kloter sumber',
];
const batchSummaryLabels = [
  'Nira yang dimasak',
  'Brix tebu acuan',
  'Jam turun',
  'Hasil timbang',
  'Bagian kloter',
];
const batchCookingLabels = [
  'Tanggal masak',
  'Jenis tebu',
  'Asal nira',
  'Tanggal',
  'Sesi',
  'Takaran gamping',
  'BTP lainnya',
  'Brix tebu acuan',
];

/// Both data sources use the demo's field order. Missing API values stay empty.
List<DemoField> detailFields(List<String> labels, List<DemoField> fields) => [
  for (final label in labels)
    fields.where((field) => field.label == label).firstOrNull ??
        DemoField(label, '—'),
];
