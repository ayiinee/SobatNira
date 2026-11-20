# Laporan: ringkasan, pagination dan batas respons

Status implementasi lokal: 21 November 2026. Lihat
[checklist optimisasi](optimization-checklist.md#d-laporan-dan-ukuran-respons).

## Kontrak API

Prefix: `/tenants/:tenantId/factories/:factoryId/production`.
Semua pembacaan tetap memeriksa membership aktif pada pabrik. Periode mengikuti
`lots.received_at`, bukan tanggal memasak; `from` inklusif dan `before` eksklusif.
Kategori sintetis/resmi tidak digabung. Tidak ada perubahan kalkulasi produksi.

| Endpoint/mode | Isi |
| --- | --- |
| `GET production-report` | Kontrak lengkap sebelumnya, kini maksimal 100 kloter |
| `GET production-report?view=summary` | `totals`, `grades`, `provisional`, `latestReceivedAt`; `items: []` |
| `GET production-report?view=page&limit=20&offset=0` | Rincian halaman, total/grade seluruh filter, `nextOffset` atau null |
| `GET profit-report`, `GET recap` | Kontrak lama dengan maksimal 100 kloter |

`production-report` menerima `from`, `before`, `synthetic`, `lotId`. `limit/offset`
hanya untuk `view=page`; validasi pagination memakai batas API yang sudah ada.
Mode summary tidak memuat JSON rincian batch. PostgreSQL menghitung total dari satu
snapshot sah terbaru per kloter dan mengagregasi grade dari batch sah. Biaya kumulatif
kloter dihitung sekali; perubahan draf koreksi tidak mengganti snapshot sah.

Mode page membaca ringkasan dan rincian dalam transaksi `REPEATABLE READ READ ONLY`.
Total dalam satu respons bukan jumlah baris halaman. Halaman kosong karena offset
melewati akhir tetap mengembalikan total lengkap. Tidak ada snapshot yang ditahan
antar-request: perubahan produksi di antara halaman dapat mengubah posisi/total;
untuk dokumen stabil gunakan snapshot ekspor, bukan menjumlahkan halaman live.

## Batas teknis

- Respons JSON laporan maksimal **5 MiB**; jika lewat, request ditolak seluruhnya.
- Laporan sinkron lengkap/laba/rekap maksimal **100 kloter**. Query mengambil satu
  baris tambahan untuk mendeteksi pelampauan, bukan mengirim 100 baris dengan total palsu.
- Rincian `production-report` maksimal **1000 batch sah per kloter**. Query mengambil
  paling banyak 1001 batch per kloter; sentinel memicu error, tidak disajikan sebagai
  laporan lengkap. Summary tidak memerlukan pemuatan rincian tersebut.
- Bila `from` dan `before` keduanya diberikan, interval maksimal **366 hari**.
  Salah satu atau keduanya boleh tidak diisi untuk summary/penelusuran semua tanggal;
  batas baris dan byte respons lengkap tetap berlaku. Ini bukan kebijakan retensi.
- Error `400` memberi arahan mempersempit periode atau menggunakan ekspor. Tidak ada
  pemotongan diam-diam, penjumlahan total halaman atau penurunan kualitas bukti.

Pembatasan respons tidak menggantikan timeout database dan pengukuran beban. Satu
kloter padat atau jumlah grade sangat besar tetap dapat membutuhkan periode lebih
sempit. Batas byte diperiksa setelah serialisasi; ini batas respons, bukan batas RAM
keras untuk seluruh proses rendering/query.

## Flutter

Beranda pada awal sesi meminta `view=summary`, sehingga tidak perlu mengunduh semua
rincian laporan. Membuka tab Laporan atau pintasan Rekap/Laba memuat rincian lengkap
sesuai periode ketika dibutuhkan. Laporan kecil tetap memakai tampilan dan cetak
yang sama. Kegagalan memuat detail tidak boleh mencetak summary sebagai dokumen lengkap.

Jika laporan lengkap melewati batas, layar menampilkan error, filter tanggal, dan
**Lihat rincian per halaman**. Layar ini mengambil 20 kloter per request, menampilkan
total seluruh periode dengan label eksplisit, navigasi sebelumnya/berikutnya dan
retry halaman yang gagal. Tidak tersedia cetak parsial pada layar ini.

Owner juga memperoleh **Ekspor laporan di server**: pilih periode, ajukan job dengan
idempotency key stabil, periksa status, lalu unduh/bagikan PDF setelah `READY`.
Permintaan gagal dapat dicoba dengan key yang sama atau direset untuk periode baru.
Admin mempersempit periode atau membaca halaman; hak ekspor owner tidak diperluas.

## Ekspor asinkron yang sudah tersedia

Endpoint pabrik `/report-exports` mempertahankan batas snapshot **500 kloter**, **5 MiB**,
dan periode eksplisit maksimal 366 hari. Karena itu tersedia jalur lebih besar dari
respons sinkron 100 kloter, tetapi bukan ekspor tanpa batas. Di atas 500 kloter,
pecah periode. Snapshot diambil saat permintaan diterima; rendering PDF/XLSX dikerjakan
worker dengan lease/retry yang sudah ada. Worker memeriksa akses owner kembali.

`REPORT_EXPORT_ENABLED=true`, migrasi report exports, R2 privat, dan worker harus
tersedia. Feature flag mati mengembalikan 503; UI tidak menyatakan job berhasil.
File diperiksa hash-nya saat diunduh. Retensi file ekspor tetap tahap terpisah.

## Profil sintetis

`npm run perf:reports` dari `apps/api` memerlukan `PERF_DATABASE_URL` lokal dengan nama
database `sobatnira_perf_*`, schema fixture Auth dan migrasi bisnis. Opsional
`PERF_REPORT_LOTS` antara 3–100 (default 30). Data dibuat melalui layanan domain:
empat batch per kloter, dua jenis grade bergantian, berat pecahan, biaya sekali per
kloter, margin negatif dan satu koreksi sah per kloter. Seluruh perubahan di-rollback.

Skrip merekam lima sampel hangat dan rencana `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`
query asli ke `.tmp/performance/reports-query-profile.json`, di luar Git.

Hasil lokal: 30 kloter, 120 batch, 120 baris grade, 150 snapshot:

| Mode | Median operasi layanan | Byte JSON |
| --- | --- | --- |
| Lengkap | 65,591 ms | 66.708 |
| Summary | 11,898 ms | 541 |
| Page 20 kloter + total lengkap | 78,479 ms | 44.775 |

Page mengurangi payload/memori client tetapi melakukan agregasi penuh dan dua query;
tidak diklaim lebih cepat untuk dataset kecil ini. Lima sampel satu koneksi lokal
tidak mewakili p95 HTTP/Auth, jaringan atau konkurensi produksi. Tidak ada indeks
tambahan diterapkan dari pengukuran ini.

## Verifikasi dan rilis

Pengujian mencakup laporan lengkap/summary/page dengan total dan grade identik,
offset melewati akhir, filter tanggal/sintetis, isolasi pabrik, koreksi aktif/dibuang/
disahkan, margin negatif, batas periode/baris/byte dan render/verifikasi PDF/XLSX.
Tes Flutter memeriksa summary awal, penolakan detail tanpa data parsial, navigasi
halaman/retry, serta Authorization dan idempotency key ekspor.

```powershell
# apps/api, DATABASE_URL dan TEST_DATABASE_URL khusus sintetis
npm run build
node --test --test-concurrency=1 test/*.test.cjs test/integration/batches-database.test.cjs test/integration/report-pagination.test.cjs

# apps/mobile
flutter analyze
flutter test
```

Deploy API terlebih dahulu, lalu Flutter; endpoint summary/page baru diperlukan klien
baru. Batas sinkron juga berlaku bagi klien lama; komunikasikan perubahan error dan
jalur ekspor. Tidak ada migrasi schema baru pada tahap ini. Rollback API/Flutter dapat
dilakukan bersama. Belum ada penerapan ke database tim/produksi atau uji R2 nyata
pada pekerjaan tahap laporan ini.
