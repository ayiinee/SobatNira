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

Migration telah diuji dalam transaksi rollback, kemudian diterapkan ke database development tim. Migration 001–016 yang sudah terpasang tidak diubah.

Koneksi PostgreSQL menggunakan CA Supabase pada `.tmp/certs/supabase-prod-ca-2021.crt`, dengan verifikasi TLS tetap aktif. `.env` lokal diarahkan ke CA ini; URL Upstash diperbaiki dari redis ke rediss. Kedua file tetap diabaikan Git. Deployment lain perlu menyediakan CA dan environment sendiri.

## Endpoint

Prefix: `/tenants/:tenantId/factories/:factoryId/production`. Semua endpoint memerlukan Supabase Bearer token dan role admin/owner dalam scope aktif.

| Method/path | Fungsi |
| --- | --- |
| GET `/batches?limit=20&offset=0` | Daftar batch dalam scope |
| POST `/batches` | Buat batch dan hasil grade; UUID yang sama dengan payload sama adalah replay |
| POST `/lots/:id/costs` | Simpan biaya sebelum pengesahan pertama |
| POST `/batches/:id/approve` | Sahkan batch, konsumsi reservasi dan simpan snapshot secara atomik |
| GET `/profit-report?from=...&before=...&synthetic=false` | Laporan snapshot terbaru per kloter, total rupiah string eksak |

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

Periode laporan mengikuti **waktu penerimaan kloter**, interval `from` inklusif dan `before` eksklusif. Hasilnya adalah snapshot terbaru dari batch yang sudah disahkan pada kloter terpilih, bukan laporan arus transaksi menurut waktu pengesahan. Batch draft tidak dihitung. Kloter dengan sebagian batch sah dapat memiliki margin sementara kumulatif dengan seluruh biaya kloter; jangan menyebutnya laba penjualan atau laba bersih final.

Jika `BATCH_API_BASE_URL` kosong, penutupan memakai pemeriksaan batch lokal. Draf atau reservasi/konsumsi yang belum terhubung batch lokal sah menghalangi penutupan. Konfigurasi upstream eksplisit tetap memakai kontrak B lama. Pemeriksaan saldo/reservasi yang sudah ada tetap berlaku.

## Seed development

Dari `apps/api`: `npm run seed:production`.

Dataset memiliki tenant sendiri, 2 pabrik dan pemasok sintetis. Seed memakai satu akun development aktif yang sudah ada untuk membership owner dataset; tidak membuat password, akun Auth atau kontak WhatsApp baru. Nama pabrik: **Pabrik Demo Variasi 1** dan **Pabrik Demo Variasi 2**. Akun yang mendapat membership adalah akun aktif dengan role owner terlebih dahulu, kemudian urutan UUID; pengguna lain memerlukan membership eksplisit oleh pengelola.

Dataset: 24 kloter, 62 batch, 48 batch sah. Termasuk penerimaan draft, penerimaan belum digiling, batch draft, reservasi aktif, sisa nira, variasi grade/harga/biaya/waktu/wajan, dan margin negatif. Ada 16 kloter bersnapshot, 8 di antaranya bermargin negatif. Seed sudah dijalankan dua kali; ID/jumlah tetap sama. Semua perubahan seed berada dalam satu transaksi dan tidak mereset data di luar dataset.

Fixture ini menggunakan `synthetic=true`. Ia tidak mengirim WhatsApp atau memanggil OCR/model. Fixture foto OCR, transfer, batch campuran dan koreksi berantai tetap terpisah dari dataset ini.

## Flutter

Pada build terhubung, login dan pilih pabrik, lalu buka **Laporan laba**. Aktifkan **Tampilkan data contoh** untuk membaca seed sintetis. Mode riil tetap default dan tidak dicampur dengan seed.

Layar memakai komponen laporan dengan pemilih periode, kartu total hijau, rincian pemasok/kloter/tanggal/margin, pagination 5 item, Cetak laporan dan Simpan PDF. Total menggunakan string eksak dari backend. Identitas kloter UUID dipakai agar kode tampilan sama tidak menghilangkan baris. Tanggal API dipertahankan, termasuk bulan di luar Oktober. Cetak/PDF memuat seluruh data snapshot yang dimuat, bukan hanya halaman aktif.

Mode Flutter tanpa konfigurasi Supabase tetap membuka demo lokal lama. Seed database tidak otomatis mengganti konstanta demo lokal tersebut.

## Batasan dan pekerjaan yang belum selesai

Implementasi ini belum menyelesaikan seluruh backlog audit. Masih diperlukan master wajan/shift/BTP, katalog harga dengan rentang berlaku, form Flutter pengelolaan batch/biaya/grade, edit/cancel/reversal batch sah, alokasi campuran, rekap produksi terhubung lengkap, penggantian semua demo/hardcode lama, penyatuan skema dan runner OCR/checksum, otomasi CI seluruh suite DB, retensi/orphan media serta latihan backup/restore. Status cancelled tersedia pada skema namun belum diekspos sebagai workflow API.

Hasil fisik dan berat grade disimpan terpisah; toleransi/kesamaan keduanya belum ditetapkan. Harga draf berasal dari input eksplisit berizin, bukan lookup katalog historis. Kehadiran snapshot tidak berarti katalog harga historis sudah selesai.

Tidak ada deployment API/aplikasi atau build APK baru pada perubahan ini. Jalankan ulang backend dari source terbaru untuk memakai endpoint tambahan.

## Verifikasi terakhir

- API: 61 lulus, 2 tes database standar dilewati. Build TypeScript lulus.
- `node --test test/integration/batches-database.test.cjs`: lulus pada fixture transaksi rollback PostgreSQL development; memeriksa replay, biaya beku, konsumsi sekali, filter, isolasi scope, serta pemeriksaan closure lokal. Perintah paket: `npm run test:batches-db`.
- Flutter: 66 lulus, 1 fixture eksternal dilewati. Tes khusus laporan terhubung juga memakai kode tampilan duplikat untuk membuktikan baris dipertahankan berdasarkan UUID kloter.
- `flutter analyze --no-fatal-infos`: keluar 0, tanpa error/warning; 68 info deprecation SDK Material.
- Seed dua kali: tetap 24 kloter, 62 batch, 48 batch sah; inspeksi baca-saja menemukan 16 kloter bersnapshot, 8 rugi, 8 variasi total gula.

## Integrasi ringkasan dan laporan Flutter

[Ringkasan dan laporan produksi terhubung](mobile-production-reports.md) melengkapi Beranda, Laporan Produksi/Margin, pintasan Laba/Rekap, serta detail grade/kloter/batch. Dokumen tersebut menjelaskan endpoint baca bersama, periode, status yang dihitung, nilai eksak dan batas margin batch. Bagian batasan di atas mencatat baseline sebelum integrasi ini.
