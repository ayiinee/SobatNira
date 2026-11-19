# Batch produksi dan laporan laba terhubung

Implementasi 19 November 2026. Ini mencatat perubahan yang benar-benar tersedia; audit sebelumnya tetap merupakan baseline historis.

## Keputusan pengguna

- NestJS repo ini memiliki batch, hasil grade, biaya dan perhitungan.
- Rendemen memakai gula grade sah / tebu netto; nilai produksi memakai harga snapshot; margin mengurangi biaya tebu, operasional, bahan dan biaya lain.
- HALF_UP diterapkan setelah menjumlah nilai grade per kloter. Snapshot bersifat kumulatif atas batch yang sudah disahkan, bukan menjumlah snapshot lama.
- Pengesahan batch campuran ditolak sampai kebijakan alokasi disepakati. Implementasi awal mensyaratkan holder dan origin reservasi sama dengan kloter batch.
- Migration dan seed diizinkan pada database development tim dari `.env`.

## Migration yang diterapkan

`017_production_batches.sql` menambahkan lima tabel, dengan RLS dan tanpa izin akses langsung anon/authenticated:

1. `production_batches`: identitas, kloter, nomor wajan, waktu, nira, hasil fisik, kategori sintetis/riil dan status.
2. `batch_grade_results`: berat serta harga per grade untuk batch; nilai harga dibekukan sejak draf batch dibuat.
3. `lot_production_costs`: biaya per kloter; perubahan ditolak setelah snapshot pengesahan pertama.
4. `production_calculation_snapshots`: input/output perhitungan kumulatif saat batch disahkan, versi formula, pelaku dan waktu.
5. `production_batch_events`: audit pembuatan/pengesahan.

Migrasi 017 sudah tersedia dari pekerjaan sebelumnya. Cabang integrasi menambahkan `018_active_batch_reservations.sql` untuk mengindeks pencarian reservasi aktif per batch. Migrasi ini diuji di database lokal dan tidak mengubah baris produksi yang sudah ada.

Koneksi PostgreSQL menggunakan CA Supabase pada `.tmp/certs/supabase-prod-ca-2021.crt`, dengan verifikasi TLS tetap aktif. `.env` lokal diarahkan ke CA ini; URL Upstash diperbaiki dari redis ke rediss. Kedua file tetap diabaikan Git. Deployment lain perlu menyediakan CA dan environment sendiri.

## Endpoint

Prefix: `/tenants/:tenantId/factories/:factoryId/production`. Semua endpoint memerlukan token Bearer Supabase dan membership pabrik. Admin dan owner boleh membaca. Penyimpanan dan pengesahan memerlukan admin.

| Method/path | Fungsi |
| --- | --- |
| GET `/batches?lotId=...&limit=20&offset=0` | Daftar batch dalam scope dengan filter kloter opsional |
| GET `/batches/:id` | Status, grade, status biaya, dan volume yang masih perlu direservasi |
| POST `/batches` | Buat batch dan hasil grade; UUID yang sama dengan payload sama adalah replay |
| POST `/lots/:id/costs` | Simpan biaya sebelum pengesahan pertama |
| POST `/batches/:id/approve` | Sahkan batch, konsumsi reservasi dan simpan snapshot secara atomik |
| POST `/batches/:id/cancel` | Batalkan draf dan lepaskan reservasinya dalam satu transaksi |
| GET `/profit-report?from=...&before=...&synthetic=false` | Laporan snapshot terbaru per kloter, total rupiah string eksak |
| GET `/recap?from=...&before=...&synthetic=false` | Snapshot yang sama beserta batch sah, grade, dan total gula |

Contoh body batch:

```json
{
 "id":"11111111-1111-4111-a111-111111111111",
 "lotId":"22222222-2222-4222-a222-222222222222",
 "code":"BATCH-001",
 "wokNumber":1,
 "occurredAt":"2026-11-19T03:00:00+07:00",
 "quantityMl":"100000",
 "physicalWeightKg":"32",
 "grades":[{"code":"A","weightKg":"30","pricePerKgRupiah":"20000"}],
 "synthetic":false
}
```

Biaya menerima empat string rupiah integer: `caneCostRupiah`, `operationalCostRupiah`, `ingredientCostRupiah`, `otherCostRupiah`.

Urutan: receipt dan milling sah → buat batch → simpan biaya kloter → reservasi nira menggunakan UUID batch melalui endpoint juice yang sudah ada → approve batch. Approval mengunci kloter dan batch, memeriksa asal/kategori/volume reservasi, lalu mengonsumsi reservasi dan membuat snapshot dalam transaksi yang sama. Retry approval mengembalikan snapshot yang sama.

Periode laporan mengikuti **waktu penerimaan kloter**, interval `from` inklusif dan `before` eksklusif. Laporan memakai snapshot terbaru dari batch sah pada setiap kloter dalam periode. Kloter terbuka memakai label margin sementara karena perhitungan kumulatif memasukkan seluruh biaya kloter.

### Penutupan kloter

Penutupan kloter operasional memeriksa batch dan stok di dalam transaksi PostgreSQL yang sama. Draf atau reservasi/konsumsi yang belum terhubung batch lokal sah menghalangi penutupan. Kontrak upstream masih tersedia untuk fixture sintetis di lingkungan development dan test.

## Seed development

Dari `apps/api`: `npm run seed:production`.

Dataset memiliki tenant sendiri, 2 pabrik dan pemasok sintetis. Seed memakai satu akun development aktif yang sudah ada untuk membership owner dataset; tidak membuat password, akun Auth atau kontak WhatsApp baru. Nama pabrik: **Pabrik Demo Variasi 1** dan **Pabrik Demo Variasi 2**. Akun yang mendapat membership adalah akun aktif dengan role owner terlebih dahulu, kemudian urutan UUID; pengguna lain memerlukan membership eksplisit oleh pengelola.

Dataset: 24 kloter, 62 batch, 48 batch sah. Termasuk penerimaan draft, penerimaan belum digiling, batch draft, reservasi aktif, sisa nira, variasi grade/harga/biaya/waktu/wajan, dan margin negatif. Ada 16 kloter bersnapshot, 8 di antaranya bermargin negatif. Seed sudah dijalankan dua kali; ID/jumlah tetap sama. Semua perubahan seed berada dalam satu transaksi dan tidak mereset data di luar dataset.

Fixture ini menggunakan `synthetic=true`. Ia tidak mengirim WhatsApp atau memanggil OCR/model. Fixture foto OCR, transfer, batch campuran dan koreksi berantai tetap terpisah dari dataset ini.

## Flutter

Pada build terhubung, login dan pilih pabrik. Sahkan nota di **Pekerjaan** dan buka **Detail Kloter** untuk melihat referensi dokumen serta menambah batch. **Detail Batch** memakai tab Ringkasan, Masak, dan Grade. Admin dapat mencatat biaya dan melanjutkan reservasi, pengesahan atau pembatalan draf. Dari Beranda atau Laporan, buka **Laba** atau **Rekap**. Aktifkan **Tampilkan data contoh** untuk membaca seed sintetis.

Layar memakai komponen laporan dengan pemilih periode, kartu total hijau, rincian pemasok/kloter/tanggal/margin, pagination 5 item, Cetak laporan dan Simpan PDF. Total menggunakan string eksak dari backend. Identitas kloter UUID dipakai agar kode tampilan sama tidak menghilangkan baris. Tanggal API dipertahankan, termasuk bulan di luar Oktober. Cetak/PDF memuat seluruh data snapshot yang dimuat, bukan hanya halaman aktif.

Mode Flutter tanpa konfigurasi Supabase tetap membuka demo lokal lama. Seed database tidak otomatis mengganti konstanta demo lokal tersebut.

## Batasan dan pekerjaan yang belum selesai

Batch baru memakai satu asal kloter dan satu grade. Alokasi campuran, koreksi batch yang sudah sah, serta katalog harga historis membutuhkan keputusan lanjutan. Master wajan/shift/BTP, retensi media dan latihan backup/restore tetap tercatat di backlog.

Hasil fisik dan berat grade disimpan terpisah; toleransi/kesamaan keduanya belum ditetapkan. Harga draf berasal dari input eksplisit berizin, bukan lookup katalog historis. Kehadiran snapshot tidak berarti katalog harga historis sudah selesai.

Tidak ada deployment API/aplikasi atau build APK baru pada perubahan ini. Jalankan ulang backend dari source terbaru untuk memakai endpoint tambahan.

## Verifikasi implementasi awal

- API: 61 lulus, 2 tes database standar dilewati. Build TypeScript lulus.
- `node --test test/integration/batches-database.test.cjs`: lulus pada fixture transaksi rollback PostgreSQL development; memeriksa replay, biaya beku, konsumsi sekali, filter, isolasi scope, serta pemeriksaan closure lokal. Perintah paket: `npm run test:batches-db`.
- Flutter: 66 lulus, 1 fixture eksternal dilewati. Tes khusus laporan terhubung juga memakai kode tampilan duplikat untuk membuktikan baris dipertahankan berdasarkan UUID kloter.
- `flutter analyze --no-fatal-infos`: keluar 0, tanpa error/warning; 68 info deprecation SDK Material.
- Seed dua kali: tetap 24 kloter, 62 batch, 48 batch sah; inspeksi baca-saja menemukan 16 kloter bersnapshot, 8 rugi, 8 variasi total gula.

## Integrasi ringkasan dan laporan Flutter

[Ringkasan dan laporan produksi terhubung](mobile-production-reports.md) melengkapi Beranda, Laporan Produksi/Margin, pintasan Laba/Rekap, serta detail grade/kloter/batch. Dokumen tersebut menjelaskan endpoint baca bersama, periode, status yang dihitung, nilai eksak dan batas margin batch. Bagian batasan di atas mencatat baseline sebelum integrasi ini.
