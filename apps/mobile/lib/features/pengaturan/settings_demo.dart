import 'package:flutter/foundation.dart';

class SettingsDemo extends ChangeNotifier {
  String gradeA = '20.000';
  String gradeB = '18.000';
  String gradeC = '15.000';
  String operationalCost = '100.000';

  void update({
    required String a,
    required String b,
    required String c,
    required String cost,
  }) {
    gradeA = a;
    gradeB = b;
    gradeC = c;
    operationalCost = cost;
    notifyListeners();
  }
}

class SettingEntry {
  const SettingEntry(this.title, this.subtitle, this.icon);

  final String title;
  final String subtitle;
  final String icon;
}

const factoryEntries = [
  SettingEntry('Identitas pabrik', 'Nama, kode, cabang, zona waktu', 'factory'),
  SettingEntry(
    'Fasilitas Produksi',
    'Wajan, kapasitas, dan status aktif',
    'factory',
  ),
  SettingEntry(
    'Pegawai & WhatsApp',
    'Tambah nomor operator dan penugasan',
    'people',
  ),
  SettingEntry('Shift kerja', 'Nama sesi, jam mulai dan selesai', 'schedule'),
  SettingEntry(
    'Hak akses & pengguna',
    'Tambah akun dan atur kewenangan',
    'security',
  ),
];

const productionEntries = [
  SettingEntry('Aturan produksi', 'Batas batch, campuran, masak ulang', 'rule'),
  SettingEntry('Grade produk', 'Jenis grade, kode, dan harga per kg', 'grade'),
  SettingEntry(
    'Bahan tambahan (BTP)',
    'Jenis bahan, satuan, dan takaran',
    'science',
  ),
  SettingEntry('Formulir produksi', 'Kelola wajib dan pemetaan OCR', 'form'),
  SettingEntry(
    'Harga & Biaya',
    'Harga jual per grade dan biaya operasional',
    'calculator',
  ),
];
