# Pool koneksi dan pemeriksaan database

API bisnis dan OCR memakai dua pool per proses NestJS. Worker OCR yang berjalan
di proses API memakai pool dokumen yang sama; worker ekspor memakai pool bisnis.
Worker atau command yang dijalankan sebagai proses terpisah perlu dihitung sendiri.
Pool dibuat saat pertama dipakai, tetapi anggaran harus memperhitungkan semua pool
yang dapat aktif, termasuk ketika replika lama dan baru bersamaan saat rollout.

## Konfigurasi

| Environment | Default | Rentang |
| --- | --- | --- |
| `DB_POOL_BUSINESS_MAX` | 5 | 1–100 per proses |
| `DB_POOL_DOCUMENTS_MAX` | 5 | 1–100 per proses |
| `DB_POOL_IDLE_MS` | 30000 | 1000–600000 ms |
| `DB_POOL_CONNECT_MS` | `CONNECTION_TIMEOUT_MS` (8000) | 100–60000 ms |
| `DB_STATEMENT_TIMEOUT_MS` | `CONNECTION_TIMEOUT_MS` (8000) | 100–600000 ms |

Batas pool dokumen kini eksplisit 5, sebelumnya default driver 10. Default gabungan
menjadi 10 per proses, bukan 15. Angka ini batas teknis awal, bukan hasil sizing
database produksi. Sampel konfigurasi akar repo memakai default tersebut. Perubahan
environment memerlukan restart; validasi menolak bilangan/rentang tidak valid tanpa
menulis nilai rahasia ke log. Konfigurasi TLS yang sudah ada tetap dipakai.

Timeout koneksi juga membatasi antrean memperoleh koneksi. `statement_timeout`
berjalan di PostgreSQL per statement; deadline driver dibuat 1 detik lebih panjang
untuk memberi kesempatan server membatalkan query. Ini bukan deadline seluruh
transaksi. Koneksi query yang gagal dibuang; rollback yang gagal juga membuang
koneksi, sehingga transaksi rusak tidak dikembalikan ke pool.

Rumus anggaran:

```text
API maksimum = jumlah proses API selama rollout × (businessMax + documentsMax)
total = API maksimum + worker terpisah + migrasi/diagnostik + aplikasi lain
total <= max_connections - koneksi reserved/provider - cadangan operasi
```

Contoh perencanaan sintetis: 2 proses × (5+5) = 20, satu command migrasi/diagnostik
menambah 1, belum termasuk layanan lain dan cadangan. Untuk produksi, isi jumlah
replika, kapasitas/provider/pooler dan cadangan aktual sebelum menaikkan batas. Jangan
memakai `max_connections` lokal sebagai kapasitas Supabase. Bila memakai transaction
pooler, verifikasi dukungan parameter sesi/timeout dan perilaku transaksi terlebih
dahulu di staging.

## Pengukuran

Kedua layanan menyediakan `poolStatistics()` internal dan log debug JSON setiap
30 detik setelah pool aktif (`event=database_pool`, `pool=business/documents`). Timer
berhenti saat shutdown dan tidak mempertahankan proses. Pada `LOG_LEVEL=info` atau
lebih ketat, log debug tidak ditampilkan. Tidak ada endpoint publik baru.

Metrik mencakup total/idle/waiting, jumlah akuisisi berhasil/gagal, total/maksimum
waktu akuisisi, serta jumlah/total/maksimum durasi transaksi sejak koneksi diperoleh
hingga commit/rollback. Waktu akuisisi juga mencakup pembukaan koneksi dan TLS; bukan
pengukuran murni antrean. Angka kumulatif di-reset saat restart. Histogram tambahan
memberikan batas atas bucket p50/p95/p99, dijelaskan pada
[observabilitas performa](performance-observability.md).
Tidak ada SQL, parameter query atau connection string dalam metrik.

Gunakan antrean, timeout, CPU/RAM database dan lock wait untuk menilai kapasitas;
menambah koneksi saat database jenuh dapat menambah latensi. Mulai dari pool kecil,
uji beban bersama dan gangguan, lalu ubah satu parameter dan bandingkan hasil.

## Diagnostik SELECT saja

Dari `apps/api`, dengan akun baca statistik yang sesuai:

```powershell
psql --dbname=$env:DATABASE_URL --no-psqlrc --set=ON_ERROR_STOP=1 --tuples-only --no-align --file=scripts/database-diagnostics.sql
```

Simpan hasil ke tempat privat di luar Git bila perlu. Query hanya membaca setting
kapasitas/autovacuum/timeout, jumlah koneksi menurut aplikasi/status/wait, umur
transaksi, ukuran tabel/index, statistik scan/dead tuple dan waktu vacuum/analyze.
Tidak mengekspor query text atau data bisnis. `canReadAllStats` dan `statsReset`
membantu menilai cakupan/umur observasi; akun biasa dapat melihat statistik sesi
lain secara terbatas.

`n_dead_tup` adalah estimasi, bukan pengukuran bloat yang akurat. `idx_scan=0` sejak
reset tidak membenarkan penghapusan index unik/PK atau index yang jarang dipakai
saat tutup buku. Jalankan selama siklus kerja representatif; tinjau statistik
planner dan autovacuum sebelum mempertimbangkan perubahan skema/parameter.

Profil laporan 30 kloter dan baseline cursor tersedia pada
[laporan](backend-report-optimization.md) dan
[pagination](backend-production-basics.md#pagination-dan-ringkasan-kloter). Indeks
batch per kloter/status dan snapshot terbaru sudah ada. Dataset tersebut belum
membuktikan perlunya indeks baru untuk antrean/review/pencarian. Tidak ada migrasi
indeks tambahan atau perubahan autovacuum dari tahap pool ini. Pengukuran kandidat
harus mencakup biaya tulis dan ukuran index; jangan memasang `pg_trgm` hanya karena
query mengandung pencarian substring.

## Verifikasi dan rollout

Tes unit memeriksa rentang konfigurasi dan instrumentasi kegagalan akuisisi. Tes
PostgreSQL dengan pool satu koneksi pada kedua jalur menguji antrean, rollback,
statement timeout dan pemulihan. Semua menggunakan database lokal sintetis.

```powershell
npm run build
node --test test/database-pool.test.cjs
# TEST_DATABASE_URL harus menunjuk database lokal sintetis
node --test test/integration/database-pool.test.cjs
```

Sebelum produksi, uji gabungan API/OCR/ekspor selama rollout, kegagalan koneksi dan
pooler di staging. Pantau waiting, timeout dan CPU database. Rollback dengan
environment sebelumnya atau versi kode sebelumnya; tidak ada migrasi schema.
Jika perlu memulihkan batas dokumen lama secara eksplisit, set
`DB_POOL_DOCUMENTS_MAX=10` hanya setelah anggaran koneksi diperiksa.
