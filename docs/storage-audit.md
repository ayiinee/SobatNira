# Simulasi inventaris dan cleanup storage

Keputusan pengguna, 21 November 2026: **simulasi cleanup saja; belum menghapus
otomatis**. Foto asli dan seluruh revisi historis tetap dilindungi. Tidak ada
penjadwal, lifecycle bucket, perubahan database, atau perintah penghapusan pada alat
ini. Kandidat berarti perlu investigasi, bukan berkas yang boleh dihapus.

## Menjalankan

Dari `apps/api`, gunakan konfigurasi lingkungan yang memang akan diaudit. CLI tidak
membaca `.env` otomatis. Jangan menyalin kredensial ke perintah, laporan atau Git.

```powershell
npm run build
$env:STORAGE_AUDIT_SOURCE='local'
$env:DOCUMENT_MEDIA_DIR='D:\path\to\synthetic-media'
# DATABASE_URL sudah tersedia melalui environment, beserta konfigurasi TLS bila perlu.
node scripts/audit-storage.cjs
```

Untuk R2, pilih `STORAGE_AUDIT_SOURCE=r2` secara eksplisit dan sediakan konfigurasi R2
yang sama dengan API. Izin storage yang diperlukan hanya `ListBucket`; tidak ada
download isi file, probe privasi yang mengunggah objek, PutObject atau DeleteObject.
Gunakan akun database yang hanya boleh SELECT semua tabel referensi. CLI mengatur
`default_transaction_read_only=on` dan snapshot `REPEATABLE READ READ ONLY` per batch.
Migrasi bisnis dan OCR, termasuk `009_media_uploads.sql`, harus tersedia. Bila salah
satu tabel/referensi tidak dapat dibaca, audit gagal; tabel yang hilang tidak dianggap
sebagai bukti bahwa objek tidak direferensikan.

Laporan JSONL lokal disimpan di `.tmp/storage-audit/` pada root repo, di luar Git.
Baris objek berisi key, kategori, ukuran, waktu perubahan, sumber referensi, versi
heuristik, alasan dan `deletionAllowed: false`. Key dapat memuat identitas internal;
perlakukan laporan sebagai data privat. Tidak ada isi foto, nomor telepon, target
pengiriman, payload OCR atau kredensial yang disalin.

## Cakupan dan klasifikasi

| Jalur | Perlakuan |
| --- | --- |
| `tenants/.../intake-documents/.../evidence/...` | Semua baris `intake_evidence` melindungi objek, termasuk yang tidak lagi aktif |
| `originals/<hash>` | Semua `media_assets` dan manifest tertaut dilindungi |
| Manifest belum tertaut | Waktu percobaan terakhir ikut diperiksa; percobaan baru dilindungi |
| `reports/<hash>` | Semua artefak dan key PDF/XLSX deterministik dari setiap job dilindungi, termasuk job gagal |
| Prefix lain, turunan gambar yang belum dikenal, fixture dan file sementara | Dilindungi sebagai kategori tidak dikenal |
| Development lokal | Hash langsung pada `DOCUMENT_MEDIA_DIR` dipetakan ke `originals/`, subdirektori `reports/` dipetakan ke `reports/` |

Semua media/evidence yang memiliki baris induk dipertahankan tanpa mengecek apakah
revisinya masih aktif. Dengan demikian submission, revisi historis, approval, job OCR
dan audit yang mengacu melalui induk tetap terlindungi. Artefak semua report job
dipertahankan tanpa syarat status atau usia; ini juga melindungi pengiriman tertunda
dan key yang diunggah sebelum transaksi penyelesaian worker berhasil. Tidak ada TTL
ekspor yang diaktifkan. Inventaris tidak menghapus metadata idempotensi/snapshot.

Objek pada jalur yang dikenal, tidak memiliki referensi yang diketahui, dan cukup
lama mendapat status `review_candidate`. Default umur **168 jam** adalah parameter
investigasi, **bukan kebijakan retensi yang disetujui**. Ubah dengan
`STORAGE_AUDIT_AGE_HOURS` (integer minimal 1). Waktu percobaan upload terbaru dan waktu
perubahan storage keduanya dipertimbangkan. Waktu yang hilang/tidak valid/di masa
depan menghasilkan perlindungan. Hash dalam nama key tidak diasumsikan sebagai hash
isi; inventaris listing tidak memverifikasi integritas foto.

## Batas dan kegagalan

- Listing R2 memakai pagination 200 objek; referensi diperiksa per 200 key. Timeout
  tiap request listing 15 detik, timeout database mengikuti konfigurasi koneksi API.
- Batas default 10.000 objek; `STORAGE_AUDIT_MAX_OBJECTS` dapat dinaikkan hingga
  1.000.000. Bila batas terlampaui, ringkasan mencatat `complete: false` dan exit code
  **2**. Ulangi dengan batas lebih tinggi untuk inventaris lengkap; jangan menilai
  angka parsial sebagai total bucket.
- Kegagalan koneksi, schema, listing atau penulisan menghasilkan exit code **1**.
  File `.partial` belum merupakan inventaris berhasil. Hanya audit yang selesai
  menulis ringkasan di-rename ke `.jsonl`. Exit code **0** berarti pemindaian selesai,
  tetap tidak mengizinkan penghapusan.
- Lokal tidak mengikuti symlink dan hanya menelusuri folder `reports` satu tingkat;
  direktori lain dicatat sebagai tidak dikenal dengan byte 0. Total byte lokal
  adalah file yang diinventaris, bukan penggunaan disk rekursif direktori asing.
- Listing storage dan snapshot referensi tidak atomik secara global. Upload atau
  pemasangan referensi dapat terjadi setelah pemeriksaan; kandidat harus diperiksa
  lagi sebelum tindakan apa pun. Protokol koordinasi/mark-and-sweep belum dibuat.
- Audit menelusuri objek yang ada; belum melaporkan semua referensi database yang
  objeknya hilang. Tidak menginventaris multipart yang belum selesai, bucket lain,
  versi objek, atau penyimpanan di luar konfigurasi aktif.

Metrik ringkasan: jumlah dan byte objek yang dipindai, jumlah per kategori, kandidat
dan estimasi byte kandidat. Registry lifecycle persisten, hash metadata terpadu,
penjadwalan, kebijakan masa simpan serta worker hapus tetap pekerjaan terpisah yang
belum diaktifkan. Review staging diperlukan sebelum keputusan kebijakan lanjutan.

## Verifikasi lokal

```powershell
# apps/api, setelah build; database khusus sintetis untuk tes integrasi
node --test test/storage-audit.test.cjs
node --test test/integration/storage-audit-database.test.cjs
```

Tes mencakup pagination listing tanpa membaca/menghapus objek, batas inventaris,
kegagalan referensi, layout lokal, waktu percobaan upload, evidence historis,
artefak ekspor dan key deterministik job gagal. Fixture PostgreSQL di-rollback.
Belum dijalankan pada bucket produksi atau staging.
