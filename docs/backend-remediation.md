# Perbaikan backend: baseline 8502004

Keputusan tim 25 November 2026: berat seluruh grade sama persis dengan berat fisik batch;
nira lintas kloter boleh dicampur; hasil setiap grade dan biaya memasak mengikuti volume
nira yang dikonsumsi; biaya tebu tetap mengikuti asal. Angka laporan adalah nilai/margin
produksi, bukan penjualan. Admin dan owner sementara dapat melihat laporan dan meminta
ekspor di pabriknya; persetujuan koreksi biaya tetap khusus owner.

Frontend tidak diubah. Reservasi lama tanpa `originLotId` tetap memakai kloter URL sebagai
asal; pencatatan campuran melalui API membutuhkan reservasi eksplisit setiap asal.
Semua nira harus sudah berada pada kloter tempat memasak: gunakan transfer yang sudah ada
sebelum reservasi. Tidak ada angka minimum liter/wajan baru dalam perubahan ini.

## Kontrak produksi v2

- Approval dan koreksi batch menolak selisih berat, termasuk 0,000001 kg. Draf belum sah
  tetap dapat menyimpan berat yang perlu diperbaiki.
- Volume sumber disimpan sebagai desimal eksak pada reservasi. Alokasi berat memakai
  satuan 0,000001 kg dan biaya memakai rupiah bulat. Sisa dibagikan menurut pecahan
  terbesar, lalu ID kloter menaik untuk hasil seri; jumlah pembagian selalu utuh.
- Biaya operasional milik kloter tempat memasak dibagi ke seluruh asal menurut konsumsi
  batch sah di kloter tersebut. Kloter tanpa batch memasak mempertahankan biaya
  operasionalnya sendiri. Biaya tebu, bahan, dan lainnya tetap pada kloter pencatat.
- Nilai produksi dihitung dari grade yang dialokasikan. Pembulatan nilai seluruh komponen
  kloter dilakukan sekali, lalu dibagi menurut nilai eksak dengan metode sisa terbesar.
- Approval baru atau koreksi membangun snapshot `production-v2` seluruh komponen kloter
  terhubung. `production-v1` dan ekspor lama tidak ditulis ulang. Snapshot baru menyimpan
  `allocatedBatches`, `sourceVolumes`, `allocationBasis`, dan versi biaya pada inputnya.
- Seluruh kloter terdampak wajib mempunyai penerimaan dan biaya tercatat serta dalam
  kondisi terbuka. Jika tertutup, buka kembali melalui prosedur yang sudah ada dahulu.
- Jumlah batch rekap dihitung berdasarkan ID unik; rincian kloter menunjukkan bagian
  batch yang dialokasikan kepadanya. Periode tetap berdasarkan penerimaan kloter.
- Mutasi nira/produksi diserialkan per pabrik. Ini batas throughput yang disengaja;
  penguncian per komponen dapat menggantikannya ketika beban membutuhkannya.

## Koreksi biaya

Prefix: `/tenants/:tenantId/factories/:factoryId/production/lots/:lotId`.

| Endpoint | Hak dan isi |
| --- | --- |
| `POST /costs` | Admin; payload lama tetap diterima. `version` opsional menolak versi usang dengan 409. Setelah snapshot pertama, gunakan koreksi. |
| `GET /cost-corrections` | Admin/owner; nilai biaya saat ini beserta `version`. |
| `POST /cost-corrections/:requestId` | Admin/owner; UUID stabil, `version`, `reason`, `caneCostRupiah`, `operationalCostRupiah`, `ingredientCostRupiah`, `otherCostRupiah`. |
| `POST /cost-corrections/:requestId/approve` | Owner; tanpa payload. Mengubah biaya dan membuat snapshot terkait dalam satu transaksi. |

Angka uang tetap string rupiah bulat nonnegatif. ID permintaan yang sama dan isi sama
mengembalikan pengajuan sebelumnya; isi berbeda atau versi usang mendapat 409.
Pengajuan ulang approval yang berhasil tidak menaikkan biaya atau membuat snapshot lagi.
Audit biaya menyimpan nilai sebelum/sesudah, pelaku, waktu, dan versi; alasan terdapat
pada pengajuan koreksi. Nilai biaya berlaku bersama untuk kategori sintetis/resmi sesuai
struktur lama; koreksi memperbarui kedua kategori jika keduanya mempunyai hasil.

Ekspor tetap milik pemohon: admin tidak dapat mengambil job/file milik owner, dan sebaliknya.
Akses dicek ulang ketika job diproses dan file diunduh. Jalur percakapan owner tetap khusus
owner; pemberian akses ekspor admin tidak membuka pairing percakapan owner.

## Migrasi dan operasional

1. Siapkan backup dan uji pemulihan pada staging. Jalankan migrasi bisnis tambahan
   `026_production_v2.sql` dengan `npm run db:migrate`.
2. Migrasi OCR menyimpan checksum. Untuk instalasi baru, `npm run db:migrate:ocr` cukup.
   Untuk histori lama tanpa checksum, review schema dan SQL yang telah diterapkan dahulu.
   Setelah review, jalankan `dist/documents/migrate.js --baseline-reviewed` dengan
   `OCR_MIGRATION_BASELINE_REVIEWED=true`. Startup menolak checksum hilang/berbeda.
   Baseline bukan bukti bahwa file historis sebelumnya selalu sama.
3. Jika worker ekspor production/connected aktif, siapkan R2 dan `R2_PUBLIC_BASE_URL`
   sebelum startup. Jangan menjadikan bucket publik untuk memenuhi variabel ini.
4. Jalankan `node scripts/check-production-weights.cjs` untuk laporan baca-saja data lama.
   Script mengikuti konfigurasi koneksi aplikasi dan tidak mengoreksi record.
5. Jalankan `node dist/documents/reconcile-media.js` untuk laporan kandidat orphan.
   `--delete` mengaktifkan penghapusan; gunakan hanya dengan database dan bucket/prefix
   khusus pasangan deployment yang sama. Default tidak menghapus apa pun.
   Objek harus berumur minimal 24 jam, tidak direferensikan, dan lolos pemeriksaan ulang
   setelah memperoleh kunci yang sama dengan intake. Penghapusan gagal menghentikan run.
   Manifest `media_uploads` juga melindungi objek, termasuk upload belum ditautkan.
   Manifest lama memerlukan review terpisah; cleanup tidak menghapusnya otomatis.
6. Sertakan `apps/api/assets/fonts` dalam paket deployment. Dockerfile sudah menyalinnya.

Schema baru mempertahankan kolom lama, tetapi aplikasi lama tidak memahami alokasi
campuran `production-v2`. Setelah transaksi v2 pertama, jangan melakukan rollback kode
ke versi lama sambil tetap menerima transaksi/laporan. Gunakan maintenance dan perbaikan
maju; pemulihan backup harus dikoordinasikan dengan seluruh transaksi setelah backup.
Sebelum aktivasi v2, uji versi lama terhadap schema baru hanya dengan data single-origin.

Paddle berjalan dalam satu proses anak per instance FastAPI, dengan satu inferensi aktif
dan deadline 180 detik. Pekerjaan sibuk/gagal menghasilkan respons sementara; antrean
NestJS mempertahankan pekerjaan untuk retry. Timeout menghentikan proses native dan
permintaan berikutnya membuat proses baru. Tidak ada antrean inferensi memori tak terbatas.

## Register temuan

| ID | Penanganan |
| --- | --- |
| BE-01 | Validasi berat sebelum approval/koreksi; pemeriksaan historis baca-saja. |
| BE-02 | **Ditunda:** ledger gula, saldo awal, dan backfill belum dibuat. |
| BE-03 | Konsumsi lintas asal, alokasi grade/biaya, snapshot seluruh kloter terkait. |
| BE-04 | Konfigurasi ekspor ditolak sejak startup jika R2/probe kurang. |
| BE-05 | Pengajuan koreksi biaya dan persetujuan owner dengan snapshot baru. |
| BE-06 | Input publik tetap 100 kelompok; kalkulasi internal tidak dibatasi 100. |
| BE-07 | **Sebagian:** audit dan versi tersedia; request frontend lama tanpa versi masih bisa menimpa edit sebelum approval. |
| BE-08 | Rekonsiliasi dan cleanup aman; operasional harus menjadwalkan run. |
| BE-09 | Pemeriksaan checksum, ukuran, dan MIME sebelum OCR/review. |
| BE-10 | Proses native berbatas waktu, penolakan saat sibuk, dan recovery. |
| BE-11 | Font Unicode backend; glyph tak didukung menghasilkan error, bukan `?`. |
| BE-12 | Checksum migrasi OCR dan baseline eksplisit setelah review. |
| BE-13–16 | **Dibatasi:** B1 tetap development-only; kelemahan internal belum diperbaiki. |
| BE-17 | Semua suite database berurutan; Auth live opt-in; smoke Paddle native pada CI. |

Inventaris B1: controller `batches`, `production-masters`, `economics` (`stock/sugar`,
`batches/:id/economics`), dan reporting lama. Caller resmi Flutter memakai endpoint scoped
`production`; fixture/skrip B1 development masih dipertahankan. Header development
tidak membuka jalur B1 pada production/connected, termasuk reset fixture batch.

## Verifikasi sebelum rilis

Jalankan `npm test`, lalu `node --test --test-concurrency=1 test/integration/*database.test.cjs`
dengan PostgreSQL sintetis. `TEST_LIVE_AUTH=true` hanya untuk pengujian Auth eksternal yang
disengaja; tes lokal tetap menguji Auth melalui stub. FastAPI: `uv run --locked python -m unittest`.
Smoke native: `uv run --locked --extra paddle python smoke_paddle.py`.

Tes mencakup alokasi 80/20, pembulatan, koreksi lintas asal, rollback snapshot, idempotency,
akses, checksum migrasi, cleanup media, Unicode, serta timeout/restart worker sintetis.
Perubahan ini belum menjalankan migrasi staging/production, cleanup live, atau pengiriman
WhatsApp. Rilis membutuhkan verifikasi staging dengan foto sintetis sampai ekspor.

Glyph PDF yang tidak tersedia mengakhiri job sebagai `FAILED` tanpa retry sia-sia;
log worker mencatat `reason: unsupported_pdf_character` tanpa isi laporan.

## Bukti verifikasi lokal, 25 November 2026

- Node 24.22.3, PostgreSQL 18 sintetis: build dan gabungan seluruh tes unit/database
  berurutan selesai dengan 104 lulus, 0 gagal, 1 tes Auth live dilewati (105 total).
  Kasus baru berada pada `apps/api/test/production-v2.test.cjs` dan
  `apps/api/test/integration/production-v2-database.test.cjs`; ekspor/admin juga diperiksa
  oleh `apps/api/test/integration/owner-agent-database.test.cjs`.
- Python 3.13.15: seluruh 17 unittest lulus, termasuk timeout dan restart proses anak.
  Smoke Paddle native dengan gambar sintetis berhasil mengenali token `12345`.
- Kontrak REST Production Insight berbasis HTTP stub: 1 tes lulus.
- Backend baseline terhadap schema baru: 4 tes batch single-origin lulus.
  Hasil ini tidak mengizinkan rollback setelah transaksi v2 pertama.
- `npm audit --omit=dev`: 0 kerentanan. `git diff --check` bersih; tidak ada diff Flutter.

Hasil lokal bukan hasil GitHub Actions atau staging. Storage memakai fixture lokal/HTTP;
R2 nyata, Auth live, dan alur WhatsApp penuh belum diverifikasi. Migrasi diuji pada database
sintetis baru; baseline checksum instalasi OCR lama tetap memerlukan review operator.

## Integrasi main terbaru

Integrasi dengan `main` commit `c741fcc` mempertahankan cache katalog, pool/metrik database,
staged upload, varian foto, pembatasan laporan, dan pagination milik tim. Ringkasan dan
halaman laporan membaca alokasi v2 sehingga batch campuran dihitung sekali dan filter
kloter hanya memuat hasil bagiannya. Tidak ada perubahan Flutter dibanding main tersebut.

Migrasi audit kini `026_production_v2.sql`; `025_catalog_cache_versions.sql` milik tim
tetap utuh. Nomor 025 untuk produksi hanya merupakan draf lokal sebelum integrasi.
Upload tetap dilakukan di luar transaksi database; manifest dilindungi dari cleanup.

Regresi gabungan lokal: 139 tes API lulus, 1 Auth live dilewati, 0 gagal (140 total),
17 tes FastAPI lulus, serta 1 tes kontrak REST berbasis stub lulus. Seluruh migrasi bisnis
gabungan berhasil diterapkan pada PostgreSQL sintetis baru.
