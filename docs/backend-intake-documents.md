# Dokumen penerimaan tebu sampai pengesahan

Backend sekarang dapat membuat draf penerimaan sintetis, menyimpan koreksi sebagai revisi, mensimulasikan konfirmasi operator, lalu mengesahkan laporan melalui admin/owner. Pengesahan mencatat penerimaan dan stok tebu masuk dalam transaksi database yang sama dengan audit.

Modul ini memakai fixture di NestJS dan tidak mengubah layanan FastAPI milik tim OCR/AI. Onboarding tidak diperlukan untuk menjalankan tes integrasi sintetis.

## Status dan batas alur

```text
draft → awaiting_validation → approved
```

| Status | Perilaku |
| --- | --- |
| `draft` | Field boleh dikoreksi dan boleh belum lengkap; belum membentuk penerimaan/stok resmi |
| `awaiting_validation` | Konfirmasi tercatat; masuk antrean admin, dapat diperiksa dan dikoreksi sebelum disahkan |
| `approved` | Revisi efektif, penerimaan dan stok masuk tersimpan; endpoint draf menolak perubahan berikutnya |

Konfirmasi sementara memakai `confirmationSource=synthetic_admin` dan identitas admin/owner yang menjalankan simulasi. Ini bukan konfirmasi WhatsApp dari operator sungguhan. Endpoint pembuatan fixture dan konfirmasi sintetis mengembalikan 404 pada `NODE_ENV=production`.

Semua dokumen/penerimaan/pergerakan yang dibuat alur ini berlabel sintetis. Saldo stok normal tidak memasukkan data tersebut; gunakan `synthetic=true` untuk melihat saldo demo. Pengesahan penerimaan tidak menyelesaikan seluruh produksi atau menutup kloter.

Foto bukti dapat diunggah dan dibaca privat melalui [modul bukti R2](backend-evidence.md), lalu terhubung ke revisi dokumen. Sumber ekstraksi fixture disimpan sebagai `sourcePayload.evidence.kind=synthetic_fixture`. Alur nota riil tersedia melalui [penerimaan dari nota OCR](#penerimaan-dari-nota-ocr).

## Endpoint

Prefix seluruh endpoint:

```text
/tenants/:tenantId/factories/:factoryId
```

Seluruh endpoint memerlukan admin/owner dengan membership aktif pada tenant/pabrik tersebut.

| Metode dan path | Fungsi |
| --- | --- |
| `POST /intake-documents/synthetic` | Membuat draf fixture untuk kloter yang sudah ada |
| `GET /intake-documents` | Daftar dokumen; filter `status`, `lotId`, `limit`, `offset` |
| `GET /intake-documents/:documentId` | Dokumen, revisi saat ini, konfirmasi dan penerimaan hasil pengesahan |
| `PATCH /intake-documents/:documentId/draft` | Koreksi field dengan pemeriksaan revisi dan alasan |
| `POST /intake-documents/:documentId/confirm-synthetic` | Simulasi konfirmasi dan masuk antrean validasi |
| `POST /intake-documents/:documentId/approve` | Pengesahan admin/owner |
| `GET /intake-documents/:documentId/revisions` | Seluruh revisi field, actor, alasan dan waktu |
| `GET /intake-documents/:documentId/history` | Audit pembuatan, koreksi, konfirmasi dan pengesahan |
| `GET /stock/sugarcane` | Saldo dari pergerakan tebu yang sudah dibukukan; filter `synthetic` dan `lotId` |

Daftar/history/revisions menggunakan envelope `{ "items": [], "total": 0, "limit": 20, "offset": 0 }`, dengan batas `limit` 1–100. Antrean Pekerjaan dapat mengambil `GET /intake-documents?status=awaiting_validation`.

## Contoh alur sintetis

### 1. Buat draf

Gunakan UUID kloter dari [modul data dasar](backend-production-basics.md) dan UUID request yang dipertahankan ketika retry:

```json
{
  "lotId": "20000000-0000-4000-8000-000000000001",
  "requestId": "50000000-0000-4000-8000-000000000001"
}
```

Respons `201` memiliki `status=draft`, `currentRevision=1`, `synthetic=true` dan field berikut:

```json
{
  "lotId": "20000000-0000-4000-8000-000000000001",
  "supplierId": "40000000-0000-4000-8000-000000000001",
  "occurredAt": "2026-11-16T01:00:00.000Z",
  "caneTypeCode": "BL",
  "netWeightKg": "1250",
  "brix": "18.5"
}
```

Lot/pemasok dan waktu awal berasal dari metadata kloter. Berat 1250 kg, kode BL dan Brix 18,5 adalah contoh sintetis. Payload sumber versi `synthetic-cane-intake-v1` dipertahankan meskipun field dikoreksi kemudian.

`requestId` unik dalam sumber/tenant/pabrik. Retry masukan yang sama mengembalikan dokumen yang sudah ada tanpa membuat revisi, event atau stok baru. Pemakaian ID yang sama untuk kloter berbeda ditolak 409. Ini adalah deduplikasi request, bukan deduplikasi isi foto; pengenalan nota yang sama dari foto berbeda masih memerlukan adapter media/OCR.

### 2. Koreksi draf

```json
{
  "expectedRevision": 1,
  "reason": "Memperbaiki berat pada fixture sintetis",
  "changes": {
    "netWeightKg": "1300.25",
    "brix": null,
    "occurredAt": "2026-11-16T09:00:00+07:00"
  }
}
```

Respons `200` menunjukkan `currentRevision=2`. Field yang dapat dikoreksi adalah `lotId`, `occurredAt`, `caneTypeCode`, `netWeightKg` dan `brix`. Pemasok selalu diambil dari kloter yang dipilih; kloter pengganti harus berada pada pabrik yang sama.

Jika foto akan dilampirkan, upload selama status masih `draft`; pemasangan foto juga menambah revisi. Gunakan `currentRevision` terbaru setelah upload ketika mengoreksi, mengonfirmasi atau mengesahkan. Revisi field mempertahankan referensi foto yang sudah terpasang.

Berat wajib berupa string desimal positif dengan titik desimal, tanpa eksponen atau pemisah ribuan. Brix berupa string desimal 0–100 atau `null`. Nilai disimpan sebagai PostgreSQL `numeric` tanpa skala tetap dan dikembalikan sebagai string, sehingga tidak melewati pembulatan floating-point. Batas 64 karakter merupakan batas ukuran input; modul tidak menetapkan kebijakan pembulatan bisnis baru.

Waktu harus berupa ISO 8601 dengan zona waktu eksplisit. Kode jenis tebu dipertahankan seperti yang diinput; fixture memakai BL, bukan katalog lengkap jenis tebu yang ditetapkan otomatis.

Draf boleh memakai `null` untuk waktu, jenis tebu atau berat yang belum terbaca. Konfirmasi dan pengesahan menolak draf yang belum lengkap. Brix bersifat opsional. Alasan koreksi wajib diisi, maksimal 500 karakter. Perubahan yang tidak mengubah nilai tidak membuat revisi baru.

### 3. Konfirmasi sintetis

```json
{ "expectedRevision": 2 }
```

Kirim ke `POST /intake-documents/:documentId/confirm-synthetic`. Respons `200` mengubah status menjadi `awaiting_validation` serta mencatat revisi, actor dan waktu konfirmasi. Retry untuk revisi yang sudah dikonfirmasi mengembalikan keadaan saat ini tanpa menambah event.

### 4. Tinjau dan sahkan

Admin/owner boleh mengoreksi field saat meninjau. Koreksi tersebut membuat revisi baru; `confirmedRevision` tetap merujuk ringkasan yang semula dikonfirmasi dan `currentRevision` menunjuk hasil pemeriksaan terbaru.

Kirim revisi terbaru ke `POST /intake-documents/:documentId/approve`:

```json
{ "expectedRevision": 2 }
```

Respons `200` memiliki `status=approved`, `approvedRevision` dan objek `intake`. Pengesahan melakukan hal berikut secara atomik:

1. Memeriksa kembali izin, status, revisi dan relasi kloter/pemasok.
2. Mencatat satu penerimaan untuk satu kloter.
3. Mencatat satu pergerakan stok masuk dengan berat persis dari revisi yang disahkan.
4. Menyamakan waktu penerimaan kloter dengan waktu kejadian pada dokumen sah, berikut audit perubahan jika waktunya berbeda.
5. Mencatat pengesahan beserta actor dan sumber revisinya.

Kegagalan salah satu langkah membatalkan seluruh transaksi. Pengesahan ulang revisi yang sama mengembalikan hasil awal tanpa menggandakan penerimaan/stok. Dokumen kedua untuk kloter yang sudah memiliki penerimaan sah ditolak 409.

Endpoint metadata kloter tetap dapat mengubah kode tampil, tetapi perubahan pemasok/waktu penerimaan setelah disahkan ditolak 409. Endpoint draf juga menolak koreksi dokumen sah. Koreksi resmi pascapengesahan akan memerlukan workflow revisi dan penyesuaian stok tersendiri; data sah tidak boleh diubah melalui jalur metadata biasa.

### 5. Periksa stok

```text
GET /stock/sugarcane?synthetic=true
```

Contoh respons:

```json
{
  "material": "sugarcane",
  "unit": "kg",
  "synthetic": true,
  "lotId": null,
  "quantityKg": "1300.25"
}
```

Tanpa `synthetic=true`, data demo tidak masuk saldo. Modul penerimaan membukukan stok masuk; [pengesahan penggilingan dari nota hasil gabungan](backend-milling-documents.md) membukukan pengeluaran tebu untuk satu kloter. Saldo menjumlahkan kedua jenis pergerakan. Saldo awal di luar penerimaan belum diimplementasikan.

## Konsistensi dan error

- `400`: format input salah, field tidak didukung, atau draf belum lengkap.
- `401`/`403`: token atau membership/role tidak memenuhi izin.
- `404`: resource tidak ditemukan dalam cakupan, atau endpoint fixture dipanggil pada production.
- `409`: revisi usang, transisi status tidak sah, ID request dipakai untuk masukan berbeda, relasi berubah, atau kloter sudah memiliki penerimaan sah.
- `503`: database/operasi penyimpanan gagal; transaksi dibatalkan.

Gunakan `currentRevision` dari hasil baca terbaru saat melakukan mutasi. Row lock menserialisasi perubahan pada dokumen/kloter; unique key dan foreign key menjaga satu penerimaan/pergerakan serta kesesuaian lot, pemasok dan jumlah. Jumlah stok tidak bisa dialihkan ke kloter lain atau diganti agar berbeda dari penerimaannya melalui penulisan tabel yang tidak konsisten.

Pola transaksi merujuk [penguncian PostgreSQL](https://www.postgresql.org/docs/current/explicit-locking.html) dan [snapshot Read Committed](https://www.postgresql.org/docs/current/transaction-iso.html). Field, revisi, status, serta jejak sumber tetap diperiksa oleh NestJS; AI hanya memasok draf.

## Penyambungan OCR berikutnya

Data field yang diperlukan untuk ekstraksi penerimaan adalah waktu kejadian, kode jenis tebu, berat bersih dalam kg dan Brix jika tersedia. ID kloter/pemasok ditautkan serta diperiksa oleh backend/admin, bukan dihasilkan atau dipercayai sebagai identitas resmi dari model AI.

`IntakeFields` di `apps/api/src/documents/intake.dto.ts` adalah bentuk draf backend saat ini. Parser memvalidasi tipe, satuan dan kelengkapan sebelum transaksi resmi. Adaptor OCR nantinya memerlukan kesepakatan request/job ID, versi nota, referensi foto privat, field ambigu, error dan retry bersama pemilik AI. Endpoint sintetis saat ini tidak menerima payload OCR arbitrer atau membuat bukti foto seolah-olah sudah diproses.

## Migrasi dan pemeriksaan

Dari `apps/api`:

```powershell
npm run db:migrate
npm test
npm run test:intake-db
```

Migrasi `003_intake_documents.sql` membuat dokumen, revisi, event, penerimaan dan pergerakan stok. Migrasi `004_intake_stock_integrity.sql` memperkuat relasi sumber pemasok/kloter dan jumlah stok. RLS aktif dan akses langsung role Supabase `anon`/`authenticated` ditutup.

Tes lokal tidak memuat kredensial asli. Tes integrasi memakai PostgreSQL development dari `.env` dan server Auth tiruan lokal sehingga onboarding tidak diperlukan. Skenario utama memakai transaksi rollback. Skenario konkurensi memerlukan beberapa koneksi: fixture sintetis dikomit sementara lalu dibersihkan berdasarkan UUID tenant/user yang dibuat khusus oleh tes, termasuk saat tes gagal. Tidak ada signup API, undangan atau pengiriman email. Tes menolak environment production dan trigger `auth.users` yang belum diperiksa.

Pemeriksaan mencakup draf tidak lengkap, koreksi setelah konfirmasi, audit/revisi, replay request, pengesahan ganda, dua dokumen untuk satu kloter, dua edit bersamaan, race perubahan metadata dengan pengesahan, rollback ketika audit gagal, desimal presisi tinggi, batas tenant/pabrik dan pemisahan saldo sintetis.

Flutter masih memakai data lokal untuk Beranda/Kloter.

## Penerimaan dari nota OCR

Untuk nota truk, pengesahan di Pekerjaan juga mencatat penerimaan resmi. Jalankan `npm run db:migrate` dan `npm run db:migrate:ocr` dari `apps/api` pada database PostgreSQL yang sama. Akun peninjau memerlukan membership aktif di workflow OCR dan akses produksi pada pabrik yang sama.

Di Pekerjaan, buka nota truk yang sudah dikonfirmasi operator. Koreksi berat bersih dalam kg dan kode jenis tebu bila perlu, lalu pilih kloter penerimaan yang sudah terdaftar beserta pemasoknya. API memakai pemasok dan waktu penerimaan yang tersimpan pada kloter pilihan. Bandingkan tanggal pada nota dengan waktu yang ditampilkan sebelum mengesahkan.

- `GET /api/v1/mobile/review-tasks/{taskId}/intake-lots?offset=0` memberi kloter pada pabrik nota yang belum punya penerimaan, beserta `supplierId`, nama pemasok, waktu penerimaan dan `next_offset`.
- `POST /api/v1/mobile/documents/{documentId}/validate` untuk nota truk mewajibkan `lot_id` dan `supplier_id` selain `revision_id`, `expected_version`, `decision: "VALIDATED"`, dan header `Idempotency-Key`. Draf, konfirmasi operator, dan koreksi admin tetap merupakan langkah sebelum pengesahan.
- Respons pengesahan dan detail tugas memuat `intake` dengan ID penerimaan, kloter, pemasok, berat, waktu dan UUID dokumen/revisi OCR. Stok tebu riil dapat dibaca di `GET /tenants/{tenantId}/factories/{factoryId}/stock/sugarcane?lotId={lotId}`.
- Pengesahan, satu penerimaan per kloter dan nota, kredit stok, serta audit disimpan dalam satu transaksi. Jika relasi berubah atau stok gagal dibukukan, tugas tetap menunggu validasi. Retry dengan kunci yang sama mengembalikan hasil tersimpan.
- Nota yang sudah disahkan sebelum fitur ini tetap ada dalam riwayat. Penerimaan historisnya perlu rekonsiliasi tersendiri.

## Koreksi stok nota sah

Pada revisi terkini yang berstatus sah di Pekerjaan, pilih **Koreksi stok nota sah**. Pilih kloter bila nota produksi mencakup beberapa blok, lalu masukkan kuantitas yang benar dan alasannya. Peninjau memerlukan akses review dan produksi pada pabrik tersebut. Jika ada revisi foto yang lebih baru, selesaikan review revisi itu dahulu.

- Nota truk memakai berat bersih dalam kg. Koreksi tersedia selama kloter masih terbuka dan tebu belum digiling.
- Nota produksi memakai volume hasil giling dalam liter. Koreksi tersedia selama kloter masih terbuka dan nira belum dipakai, tidak memiliki reservasi aktif, serta belum terlibat dalam transfer. Reservasi yang sudah dilepas tidak mengurangi saldo.
- API menerima `POST /api/v1/mobile/documents/{documentId}/reconcile` dengan `Idempotency-Key` dan body `{revision_id, expected_version, lot_id, quantity, reason}`. `quantity` adalah nilai akhir dalam string desimal, bukan selisih.
- Respons mengembalikan task dan revisi sah baru serta `reconciliation` dengan kuantitas sebelum, sesudah, selisih, dan alasan. Tindakan yang sama dapat diulang dengan kunci yang sama. Koreksi terhadap revisi usang atau stok yang sudah terpakai menghasilkan 409.
- Posting awal tetap tersimpan. Ledger memasukkan selisih koreksi, sedangkan detail kloter menunjukkan berat efektif dan referensi revisi yang memperbarui stok. Layar Pekerjaan menampilkan riwayat koreksi pada tiap revisi.
