// Deterministic synthetic presentation data shared by lists, charts and details.
class DemoLotFixture {
  const DemoLotFixture(
    this.code,
    this.day,
    this.supplier,
    this.caneKg,
    this.sugarKg,
    this.marginRupiah,
    this.batchCount,
  );
  final String code, supplier;
  final int day, caneKg, sugarKg, marginRupiah, batchCount;
  List<int> get batchWeights {
    final weights = <int>[];
    var remaining = sugarKg;
    for (var i = 0; i < batchCount; i++) {
      final value = i == batchCount - 1
          ? remaining
          : sugarKg ~/ batchCount + (i % 3 - 1);
      weights.add(value);
      remaining -= value;
    }
    return weights;
  }

  int get productionValue {
    var total = 0;
    for (var i = 0; i < batchCount; i++) {
      total += batchWeights[i] * [20000, 18000, 15000][i % 3];
    }
    return total;
  }

  int get totalCost => productionValue - marginRupiah;
}

const demoLotFixtures = [
  DemoLotFixture('MJT-260926-1A', 20, 'Sugeng', 1500, 90, 570000, 5),
  DemoLotFixture('MJT-260926-2A', 20, 'Slamet', 1240, 72, 230000, 3),
  DemoLotFixture('MJT-260926-3A', 20, 'Darto', 1800, 126, 1140000, 4),
  DemoLotFixture('MJT-250926-1A', 19, 'Mulyanto', 980, 58, 430000, 2),
  DemoLotFixture('MJT-250926-2A', 19, 'Masud', 2150, 151, 800000, 6),
  DemoLotFixture('MJT-240926-1A', 18, 'Salim', 1325, 63, 195000, 3),
  DemoLotFixture('MJT-240926-2A', 18, 'Mawarji', 1670, 70, -85000, 4),
  DemoLotFixture('MJT-230926-1A', 17, 'Hadi', 1140, 85, 670000, 5),
  DemoLotFixture('MJT-230926-2A', 17, 'Joko', 1960, 95, 350000, 4),
  DemoLotFixture('MJT-220926-1A', 16, 'Wahyu', 1435, 80, 900000, 3),
  DemoLotFixture('MJT-220926-2A', 16, 'Budi', 1580, 100, 420000, 6),
  DemoLotFixture('MJT-210926-1A', 15, 'Rini', 1210, 88, 780000, 4),
  DemoLotFixture('MJT-200926-1A', 14, 'Sutrisno', 1740, 121, -125000, 7),
  DemoLotFixture('MJT-190926-1A', 13, 'Warto', 2080, 145, 685000, 5),
  DemoLotFixture('MJT-180926-1A', 12, 'Sari', 1360, 87, 245000, 3),
  DemoLotFixture('MJT-170926-1A', 11, 'Tono', 1620, 108, 390000, 4),
];
DemoLotFixture demoLotFor(String code) => demoLotFixtures.firstWhere(
  (lot) => lot.code == code,
  orElse: () => DemoLotFixture(code, 20, 'Pemasok Demo', 1500, 90, 570000, 5),
);
String demoNumber(num value, {int decimals = 0}) {
  final parts = value.toStringAsFixed(decimals).split('.');
  final negative = parts[0].startsWith('-');
  final digits = negative ? parts[0].substring(1) : parts[0];
  return '${negative ? '-' : ''}${digits.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.')}${decimals > 0 ? ',${parts[1]}' : ''}';
}

String demoMoney(int value) =>
    '${value < 0 ? '-' : ''}Rp${demoNumber(value.abs())}';
