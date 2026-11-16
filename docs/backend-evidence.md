# Foto bukti nota di R2

Foto bukti penerimaan dapat diunggah melalui NestJS dan disimpan di bucket R2 privat. Endpoint baca memeriksa token serta akses tenant/pabrik pada setiap request, lalu memeriksa integritas berkas sebelum mengirim byte foto. Draf ekstraksi tetap memakai fixture sintetis selama OCR belum dihubungkan.

## Alur

1. Buat pemasok/kloter dan draf melalui `POST /intake-documents/synthetic`.
2. Upload foto pada dokumen berstatus `draft` dengan `expectedRevision` saat ini.
3. Backend memvalidasi foto, menyimpan objek baru di R2 dan memasang referensi dalam revisi dokumen baru.
4. Baca `evidence.contentPath` menggunakan client HTTP yang mengirim Bearer token.
5. Lakukan koreksi field jika diperlukan, konfirmasi sintetis dan pengesahan memakai nomor revisi terbaru.

Upload foto tidak memproses OCR atau mengganti nilai fixture secara otomatis. `sourcePayload` tetap menunjukkan sumber ekstraksi sintetis; foto yang benar-benar diunggah muncul pada properti `evidence` dokumen. Flag sintetis pada dokumen tidak berarti file yang diberikan pengguna merupakan data sintetis.

## Endpoint

Prefix:

```text
/tenants/:tenantId/factories/:factoryId/intake-documents/:documentId
```

| Metode dan path | Fungsi |
| --- | --- |
| `POST /evidence` | Upload satu foto dan pasang ke revisi baru |
| `GET /evidence` | Daftar foto yang pernah dipasang pada dokumen; menerima `limit`/`offset` |
| `GET /evidence/:evidenceId/content` | Baca byte foto asli melalui otorisasi backend |

Admin dan owner dengan membership aktif pada pabrik tersebut dapat mengakses endpoint ini. ID foto tetap harus dimiliki dokumen pada URL, meskipun caller juga memiliki akses ke dokumen atau pabrik lain.

### Upload multipart

Field yang diterima:

| Field | Nilai |
| --- | --- |
| `file` | Satu JPEG, PNG atau WebP; MIME harus sesuai isi berkas |
| `requestId` | UUID stabil untuk retry upload ini |
| `expectedRevision` | Nomor revisi dokumen, dikirim sebagai teks multipart |
| `reason` | Alasan pemasangan/penggantian bukti, 1–500 karakter |

Batas teknis awal adalah 8 MiB dan 20 megapiksel. Backend memeriksa signature, metadata, jumlah halaman dan hasil decode gambar, lalu menghitung SHA-256. Byte asli disimpan tanpa resize atau pengubahan metadata. Nama file dari klien tidak dipakai sebagai object key maupun filename respons. SVG, PDF, MIME palsu, file rusak dan foto di luar batas ditolak.

Contoh dari terminal yang sudah memiliki token, tenant/pabrik dan dokumen development:

```powershell
curl.exe -X POST "http://127.0.0.1:3000/tenants/TENANT_ID/factories/FACTORY_ID/intake-documents/DOCUMENT_ID/evidence" `
  -H "Authorization: Bearer ACCESS_TOKEN" `
  -F "requestId=50000000-0000-4000-8000-000000000001" `
  -F "expectedRevision=1" `
  -F "reason=Foto nota sintetis untuk demo" `
  -F "file=@D:/fixtures/nota-sintetis.png;type=image/png"
```

Gunakan `FormData` atau encoder multipart pada klien; biarkan encoder menetapkan boundary Content-Type. Jalur foto pada contoh adalah placeholder lokal, bukan file fixture yang disertakan dalam Git.

Respons `201` berbentuk:

```json
{
  "document": {
    "id": "60000000-0000-4000-8000-000000000001",
    "status": "draft",
    "currentRevision": 2,
    "synthetic": true,
    "evidence": { "id": "70000000-0000-4000-8000-000000000001" }
  },
  "evidence": {
    "id": "70000000-0000-4000-8000-000000000001",
    "documentId": "60000000-0000-4000-8000-000000000001",
    "contentType": "image/png",
    "byteSize": 12345,
    "width": 1200,
    "height": 1600,
    "sha256": "HASH_SHA256_BERKAS",
    "contentPath": "/tenants/TENANT_ID/factories/FACTORY_ID/intake-documents/DOCUMENT_ID/evidence/EVIDENCE_ID/content"
  }
}
```

Contoh respons dipersingkat; metadata juga memuat uploader dan waktu. API tidak mengembalikan object key, nama bucket, credential atau URL R2 langsung. `contentPath` adalah path relatif ke API dan tetap membutuhkan Authorization.

### Baca foto

Client melakukan GET ke `contentPath` dengan Bearer token, lalu menampilkan byte yang diterima. Endpoint mengembalikan Content-Type terverifikasi, filename yang dibuat server, `Cache-Control: private, no-store` dan `X-Content-Type-Options: nosniff`.

Panjang, MIME dan hash byte dari R2 diperiksa terhadap metadata database. Foto yang hilang, berubah, terpotong atau tidak dapat dibaca menghasilkan 503. Akses tanpa token ditolak 401; akses resource dari cakupan/dokumen lain ditolak tanpa membaca foto di R2. Pencabutan membership berlaku pada request berikutnya. Foto yang sudah diunduh oleh pengguna tentu berada di luar kontrol permintaan berikutnya.

Browser mengakses API sehingga jalur ini menggunakan CORS API yang sudah dikonfigurasi. Jalur proxy ini tidak memerlukan browser melakukan upload atau membaca langsung dari origin R2. Variabel TTL signed URL tidak digunakan untuk akses foto ini.

## Revisi, retry dan penggantian

- Pemasangan pertama membuat revisi baru dengan origin `evidence_attachment` dan event audit `evidence_attached`.
- Penggantian foto hanya tersedia selama status `draft`; backend membuat objek R2 baru. Foto sebelumnya tetap terhubung ke revisinya dan dapat dibaca melalui endpoint berizin.
- Koreksi field berikutnya mempertahankan ID bukti pada revisi baru.
- Setelah `awaiting_validation` atau `approved`, upload baru ditolak 409. Tidak ada endpoint penghapusan bukti tertaut.
- Retry dengan request ID, file, alasan dan expected revision yang sama mengembalikan lampiran sebelumnya tanpa membuat objek/revisi tambahan yang tertaut.
- Request ID yang dipakai dengan masukan berbeda atau nomor revisi usang ditolak 409. Pada retry lama, respons tetap memuat dokumen saat ini dan metadata foto milik request asli; foto tersebut mungkin sudah menjadi bukti pada revisi historis.

Upload R2 berjalan sebelum transaksi pemasangan. Izin, status dan revisi diperiksa kembali setelah upload. Metadata foto, pointer dokumen, revisi dan event audit dipasang atomik di PostgreSQL. Percobaan upload bersamaan memakai object key berbeda agar percobaan yang kalah dapat dibersihkan tanpa menimpa foto pemenang.

Jika pemasangan gagal, backend menghapus hanya objek baru yang dapat dipastikan belum direferensikan database. Advisory lock per object key membuat pemeriksaan pembersihan menunggu transaksi pemasangan selesai sebelum membaca hasil commit. Bila database tidak bisa diperiksa, backend mempertahankan objek privat dan mencatat perlunya pemeriksaan pembersihan. Ini menghindari penghapusan bukti yang mungkin sudah berhasil disimpan. Rekonsiliasi orphan saat gangguan panjang dan kebijakan retensi bukti tertaut belum diotomatisasi; keputusan retensi tetap perlu disepakati tim.

## Konfigurasi bucket privat

Gunakan kredensial R2 yang sudah tersedia pada `.env` akar repo. Bucket bukti wajib menonaktifkan Public Development URL (`r2.dev`) serta seluruh custom domain publik. Kredensial S3 untuk operasi objek tidak dapat mengubah pengaturan publik Cloudflare.

`R2_PUBLIC_BASE_URL`, bila diisi, hanya dipakai untuk pengujian negatif akses anonim. Sebelum mengirim foto pengguna, backend mengunggah marker sintetis tanpa data pengguna, mencoba akses anonim pada alamat tersebut, lalu menghapus marker. Upload ditolak 503 bila alamat masih terbuka atau pemeriksaan tidak dapat diselesaikan. Hanya 401/403/404 yang diterima sebagai penolakan akses.

Pemeriksaan alamat yang terkonfigurasi tidak menginventaris seluruh custom domain akun Cloudflare. Operator tetap harus memastikan seluruh akses publik bucket dinonaktifkan. Jangan mengaktifkan kembali alamat publik hanya untuk menjalankan pemeriksaan ini. Bila URL tidak dikonfigurasi, prasyarat bucket privat tetap berlaku.

Lihat [pengaturan public bucket R2](https://developers.cloudflare.com/r2/buckets/public-buckets/). Pengaturan sudah diverifikasi ulang pada development setelah akses publik dinonaktifkan.

## Error dan pengujian

| Status | Arti |
| --- | --- |
| `400` | Field multipart, MIME/isi gambar, dimensi atau file tidak valid |
| `401`/`403` | Token atau izin tidak memenuhi akses |
| `404` | Dokumen/foto tidak ditemukan dalam cakupan |
| `409` | Revisi usang, dokumen sudah dikonfirmasi, atau request ID dipakai ulang untuk masukan berbeda |
| `413` | Berkas melebihi 8 MiB |
| `503` | R2/database tidak tersedia, privasi tidak terverifikasi atau integritas foto tidak sesuai |

Dari `apps/api`:

```powershell
npm run db:migrate
npm test
npm run test:evidence-db
npm run test:evidence-r2
```

Migrasi `005_intake_evidence.sql` menambahkan metadata foto, pointer bukti per dokumen/revisi dan jenis event audit. RLS aktif dan role Supabase klien tidak diberi akses langsung.

Tes lokal memakai gambar sintetis dan S3 HTTP tiruan. `test:evidence-db` memakai PostgreSQL development dan S3 tiruan untuk alur multipart, revisi, penggantian, baca foto, retry bersamaan, perubahan izin, kompensasi kegagalan dan penolakan bucket publik. `test:evidence-r2` secara eksplisit mengunggah gambar sintetis ke R2 nyata, membaca byte melalui API, memeriksa penolakan anonim, lalu menghapus objek serta data fixture yang dibuat khusus tes. Onboarding tidak diperlukan karena Auth tiruan hanya dipakai dalam harness tes.

Seluruh fixture berupa data sintetis. Foto nota asli dan credential tidak dimasukkan Git. Integrasi OCR, WhatsApp dan layar Flutter tetap dikerjakan melalui kontrak layanan masing-masing.
