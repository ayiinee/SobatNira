import 'package:flutter/foundation.dart';

class SettingsDemo extends ChangeNotifier {
  FactoryProfile factory = (
    name: 'Pabrik Demo',
    code: 'PBR-DEMO',
    branch: 'Cabang Demo',
    timezone: 'Asia/Jakarta',
  );
  String batchLimit = '115';
  String operationalCost = '100.000';
  int _nextId = 10;

  final pans = [
    for (var i = 1; i <= 3; i++)
      DemoItem(i, (name: 'Wajan $i', capacity: '115')),
  ];
  final operators = [
    const DemoItem(1, (
      name: 'Operator Demo',
      phone: '+6280000000000',
      assignment: 'Pencatatan produksi',
    )),
  ];
  final shifts = [
    const DemoItem(1, (name: 'Pagi', start: '07:00', end: '15:00')),
    const DemoItem(2, (name: 'Sore', start: '15:00', end: '23:00')),
  ];
  final accounts = [
    const DemoItem(1, (
      name: 'Pak Putu Alvin',
      email: 'owner@example.invalid',
      role: DemoRole.owner,
    )),
    const DemoItem(2, (
      name: 'Admin Demo',
      email: 'admin@example.invalid',
      role: DemoRole.admin,
    )),
  ];
  static const currentAccountId = 1;

  final grades = [
    for (final (index, code) in ['A', 'B', 'C'].indexed)
      DemoItem(index + 1, (name: 'Grade $code', code: code)),
  ];
  final additives = [
    const DemoItem(1, (name: 'Gamping', unit: 'Takaran asli', amount: '')),
  ];
  final _prices = <int, String>{1: '20.000', 2: '18.000', 3: '15.000'};
  final _aliases = <String, List<String>>{};

  String? priceFor(int gradeId) => _prices[gradeId];
  List<String> aliasesFor(String field) =>
      List.unmodifiable(_aliases[field] ?? const <String>[]);

  void saveFactory(FactoryProfile value) {
    factory = value;
    notifyListeners();
  }

  void saveBatchLimit(String value) {
    batchLimit = value;
    notifyListeners();
  }

  void saveItem<T>(
    List<DemoItem<T>> items,
    DemoItem<T>? previous,
    T value, {
    required bool active,
  }) {
    if (previous == null) {
      items.add(DemoItem(_nextId++, value, active: active));
    } else {
      final index = items.indexWhere((item) => item.id == previous.id);
      items[index] = DemoItem(previous.id, value, active: active);
    }
    notifyListeners();
  }

  void savePrices(Map<int, String> prices, String cost) {
    for (final entry in prices.entries) {
      if (entry.value.isEmpty) {
        _prices.remove(entry.key);
      } else {
        _prices[entry.key] = entry.value;
      }
    }
    operationalCost = cost;
    notifyListeners();
  }

  void addAlias(String field, String alias) {
    _aliases.putIfAbsent(field, () => []).add(alias);
    notifyListeners();
  }

  void removeAlias(String field, String alias) {
    _aliases[field]?.remove(alias);
    notifyListeners();
  }
}

typedef FactoryProfile = ({
  String name,
  String code,
  String branch,
  String timezone,
});
typedef DemoPan = ({String name, String capacity});
typedef DemoOperator = ({String name, String phone, String assignment});
typedef DemoShift = ({String name, String start, String end});
typedef DemoAccount = ({String name, String email, DemoRole role});
typedef DemoGrade = ({String name, String code});
typedef DemoAdditive = ({String name, String unit, String amount});

enum DemoRole {
  admin('Admin'),
  owner('Owner/Manager');

  const DemoRole(this.label);
  final String label;
}

class DemoItem<T> {
  const DemoItem(this.id, this.value, {this.active = true});

  final int id;
  final T value;
  final bool active;
}

enum SettingSection {
  identity,
  facilities,
  operators,
  shifts,
  access,
  rules,
  grades,
  additives,
  forms,
  prices,
}

class SettingEntry {
  const SettingEntry(this.section, this.title, this.subtitle, this.icon);

  final SettingSection section;
  final String title;
  final String subtitle;
  final String icon;
}

const factoryEntries = [
  SettingEntry(
    SettingSection.identity,
    'Identitas pabrik',
    'Nama, kode, cabang, zona waktu',
    'factory',
  ),
  SettingEntry(
    SettingSection.facilities,
    'Fasilitas Produksi',
    'Wajan, kapasitas, dan status aktif',
    'facilities',
  ),
  SettingEntry(
    SettingSection.operators,
    'Pegawai & WhatsApp',
    'Tambah nomor operator dan penugasan',
    'people',
  ),
  SettingEntry(
    SettingSection.shifts,
    'Shift kerja',
    'Nama sesi, jam mulai dan selesai',
    'schedule',
  ),
  SettingEntry(
    SettingSection.access,
    'Hak akses & pengguna',
    'Tambah akun dan atur kewenangan',
    'security',
  ),
];

const productionEntries = [
  SettingEntry(
    SettingSection.rules,
    'Aturan produksi',
    'Batas batch, campuran, masak ulang',
    'rule',
  ),
  SettingEntry(
    SettingSection.grades,
    'Grade produk',
    'Jenis grade, kode, dan harga per kg',
    'grade',
  ),
  SettingEntry(
    SettingSection.additives,
    'Bahan tambahan (BTP)',
    'Jenis bahan, satuan, dan takaran',
    'science',
  ),
  SettingEntry(
    SettingSection.forms,
    'Formulir produksi',
    'Kelola wajib dan pemetaan OCR',
    'form',
  ),
  SettingEntry(
    SettingSection.prices,
    'Harga & Biaya',
    'Harga jual per grade dan biaya operasional',
    'calculator',
  ),
];
