import 'package:sobatnira/features/pekerjaan/review_api.dart';

Json largeReportFixture() {
  const weight = '1234567.125';
  const money = '900719925474099312345';
  final calculation = {
    'finalSugarKg': weight,
    'rendemenPercent': '12.3456789',
    'productionValueRupiah': money,
    'totalCostRupiah': '1234567890123456',
    'productionMarginRupiah': '-1234567890123456',
    'costs': {
      'caneRupiah': '1234567890123456',
      'operationalRupiah': '100000',
      'ingredientRupiah': '50000',
      'otherRupiah': '0',
    },
  };
  final batch = {
    'id': 'batch',
    'code': 'BATCH-SINTETIS-PANJANG-001',
    'wokNumber': 1,
    'occurredAt': '2026-11-10T02:00:00Z',
    'quantityMl': '83500125.123456789',
    'physicalWeightKg': weight,
    'finalSugarKg': weight,
    'exactValueRupiah': money,
    'grades': [
      {'code': 'A', 'weightKg': weight, 'pricePerKgRupiah': '1234567890123456'},
    ],
  };
  return {
    'items': [
      {
        'lotId': 'lot',
        'code': 'KLOTER-SINTETIS-PANJANG-001',
        'supplier': 'Pemasok sintetis dengan nama panjang untuk uji tampilan',
        'receivedAt': '2026-11-10T02:00:00Z',
        'caneNetKg': '12345678.901234',
        'juiceLiters': '1234567.123456',
        'caneType': 'BL',
        'closed': true,
        'calculation': calculation,
        'batches': [batch],
      },
    ],
    'grades': [
      {'code': 'A', 'weightKg': weight, 'exactValueRupiah': money},
    ],
    'totals': {
      ...calculation,
      'caneNetKg': '12345678.901234',
      'lotCount': 1,
      'producedLotCount': 1,
      'batchCount': 1,
    },
  };
}
