# Produksi, stok gula, dan rework

Kontrak tambahan untuk A1–A4, berbasis `b20abf8`, terintegrasi dengan `main` `04306e3`. Kalkulasi, otorisasi, penguncian, dan pencatatan resmi berada di NestJS. Endpoint B1 tidak digunakan.

## Kontrak API

Prefix: `/tenants/:tenantId/factories/:factoryId/production`. Admin menulis, admin/owner membaca. Kategori sintetis terpisah dari kategori resmi; master berlaku per pabrik.

| Endpoint | Isi |
| --- | --- |
| `GET /batches/:id` | Reservasi semua asal, sisa volume, provenance nota, jenis batch, status finansial. |
| `GET /lots/:id/batch-sources` | Baris revisi nota sah terbaru; `source` berisi `documentId`, `revisionId`, `block`, `rowReference`. |
| `POST /batches` | Payload lama tetap berlaku. Tambahan opsional `source`, `kind` (`normal`/`rework`), dan `masterReferences`. Maksimum 100 grade. |
| `GET /sugar?synthetic=false` | Aktivasi, versi, sumber stok, saldo/reservasi/tersedia, total bruto dan pemakaian rework. |
| `GET /sugar/history?synthetic=false&limit=20&offset=0` | Mutasi bertanda, alasan, waktu, pelaku, sumber, dan ID kejadian. |
| `POST /sugar/opening` | `requestId`, `version:0`, `reason`, `synthetic`, `items:[{gradeCode,quality,weightKg,batchId?,originLotId?}]`. Grade aktif wajib tersedia. |
| `POST /sugar/adjustments` | Field mutasi bersama, `sourceId`, `weightKg`, `direction:add/subtract`. |
| `POST /sugar/quality` | Field mutasi bersama, `sourceId`, `weightKg`, kualitas tujuan `quality:good/failed`. |
| `POST /sugar/rework-enablement` | Field mutasi bersama dan `reportHandlingConfirmed:true`; tidak diaktifkan otomatis. |
| `POST /batches/:id/rework-inputs` | Field mutasi bersama, `sourceId`, `weightKg`. |
| `GET /batches/:id/traceability` | Sumber dan penerima gula, asal nira, nota, koreksi, alokasi versi, hasil bruto/terpakai/bersih. |
| `GET /masters?history=true&synthetic=false` | Wajan/grade beserta versi, status dan riwayat; statistik menghitung batch fisik unik. |
| `POST /masters` | `requestId`, `kind:wok/grade`, `code`, `version`, `name`, `active`, `reason`; wajan wajib `capacityLiters`. Versi 0 untuk entri baru. |

Mutasi stok memakai versi dari `GET /sugar`. UUID retry dan payload harus identik. Versi usang atau UUID dengan isi berbeda mendapat 409. Setelah respons ambigu, ulangi permintaan yang sama; jangan membuat UUID pengganti. Respons mutasi berisi versi terbaru; baca ulang sebelum mutasi berikutnya. Approval dan pembatalan menggunakan kontrak batch yang sudah ada.

`masterReferences` berbentuk `{wok:{code:"1",version:1},grades:[{code:"A",version:1}]}`. Referensi harus cocok dengan nomor wajan/kode grade batch dan versi aktif saat pembuatan. Versi tersimpan pada batch; penonaktifan berlaku untuk pilihan baru. Payload manual lama tanpa referensi tetap diterima. Kapasitas hanya informasi.

## Aturan pencatatan

- Saldo awal memakai hitung fisik saat aktivasi. Asal yang tidak diketahui diberi label; tidak ada rekonstruksi transaksi lama.
- Approval setelah aktivasi mengakui hasil satu kali, sekalipun waktu masak diisi mundur. Koreksi hasil menambah entri selisih dalam transaksi yang sama. Koreksi batch sebelum aktivasi tidak mengubah saldo awal.
- Berat memakai string desimal maksimum enam angka pecahan kg. Alokasi mengikuti rasio nira dengan sisa pecahan terbesar dan ID asal sebagai pemecah seri.
- Reservasi sumber tidak tersedia bagi batch lain. Pembatalan melepaskannya. Sumber kloter tertutup memerlukan pembukaan kembali dengan alasan.
- Rework wajib gula sumber dan nira baru. Hasil baru dialokasikan menurut nira baru. Contoh 3 kg hasil, 2 kg gula terpakai, tambahan bersih 1 kg. Penyusutan boleh menghasilkan tambahan bersih negatif.
- Pengiriman dan penjualan belum dicatat. Saldo API/UI menyebut keterbatasan tersebut.

## Handoff Ferdi: laporan dan aktivasi

Laporan rupiah yang mencakup kloter/rangkaian alokasi terdampak mendapat HTTP 409:

```json
{"code":"REWORK_FINANCIALS_PENDING","message":"Nilai dan margin kloter rework belum tersedia. Laporan gabungan belum lengkap.","affectedLotIds":["uuid-kloter"]}
```

Flutter laporan/ekspor harus menjelaskan nilai belum tersedia dan tidak menggantinya dengan angka nol atau snapshot lama sebagai nilai terkini. Query stok, hasil berat, dan traceability tetap tersedia. Snapshot dan unduhan ekspor yang sudah dibuat tetap dipertahankan. Ekspor baru mengikuti penolakan laporan resmi. Rumus rupiah rework dan metode biaya pada file bersama tetap memerlukan integrasi Ferdi.

Urutan aktivasi pilot: master grade/wajan → hitung fisik dan saldo awal → pencatatan stok → konfirmasi penanganan laporan Ferdi → aktivasi rework. Tidak ada aktivasi rework atau migrasi production otomatis.

## Migrasi dan verifikasi

Migrasi tambahan 027–031: provenance nota, ledger, rework, master berversi, penguatan kelengkapan identitas baris. Tidak mengedit migrasi yang sudah diterapkan. Tabel baru menggunakan RLS dan mencabut akses role browser.

Database sintetis terisolasi dipakai untuk tes API. Jalankan dari `apps/api`:

```sh
npm test
node --test --test-concurrency=1 test/integration/*database.test.cjs test/integration/report-pagination.test.cjs test/integration/database-pool.test.cjs
```

Dari `apps/mobile`: `flutter analyze` dan `flutter test`. Untuk lintas aplikasi, jalankan `node scripts/mobile-production-fixture.cjs --transfer` pada API dengan `TEST_DATABASE_URL` lokal. Teruskan JSON `PRODUCTION_TEST_*` sebagai `--dart-define` ke `flutter test test/features/kloter/production_inventory_backend_test.dart`. Fixture menyimpan perubahan dalam transaksi rollback, hentikan server setelah tes. Jangan memakai database mitra.

Staging, WhatsApp nyata, dan perangkat Android nyata belum menjadi bukti uji lokal ini. Sebelum pilot: uji migrasi staging, rekonsiliasi saldo fisik, persetujuan kontrak laporan Ferdi, lalu acceptance demo dipimpin Ferdi.

## Register lingkup audit

| Butir | Status dalam pekerjaan ini |
| --- | --- |
| BE-02 ledger gula | Ledger resmi, aktivasi fisik, koreksi, kualitas dan konsumsi rework tersedia. Pengiriman, backfill dan nilai rework tetap terbuka. |
| Campuran/berat | API dan Flutter mendukung beberapa asal/grade; approval menegakkan kesamaan berat dan alokasi eksak. |
| Nota ke batch | Identitas baris unik lintas revisi; revisi usang ditolak, nomor wajan berulang bukan duplikat. |
| Master | Persistensi dan riwayat wajan/grade tersedia. Sif, BTP dan pemetaan OCR tetap pratinjau. |
| Kesiapan rilis | Menunggu staging, perangkat nyata, rekonsiliasi pilot dan konfirmasi integrasi laporan. |
