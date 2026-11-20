# Cache katalog dengan invalidasi dari PostgreSQL

Cache-aside tersedia untuk **daftar pemasok** dan **daftar jenis tebu**, termasuk
filter, limit dan offset. Detail/history, daftar kloter, laporan, stok/reservasi,
konfirmasi/pengesahan, biaya, koreksi dan penutupan tetap membaca database. Tidak ada
perubahan angka produksi atau keputusan resmi yang bergantung pada Redis.

Default **nonaktif**. Aktifkan setelah migrasi dan uji staging, dengan environment:

```dotenv
CATALOG_CACHE_ENABLED=true
CATALOG_CACHE_TTL_SECONDS=300
CATALOG_CACHE_TIMEOUT_MS=100
```

`REDIS_URL` harus tersedia melalui konfigurasi privat. TLS/provider mengikuti URL
yang divalidasi backend. TTL menerima 1–3600 detik, timeout 20–1000 ms. Flag/URL yang
tidak tersedia memakai jalur database biasa tanpa query versi tambahan. Flag mati
tidak mengubah autentikasi/otorisasi pada repository/controller.

## Konsistensi dan akses

Migrasi bisnis **025_catalog_cache_versions.sql** menambahkan satu generasi UUID per
tenant/katalog. Trigger statement-level menangani INSERT/UPDATE/DELETE dan TRUNCATE.
Bulk import mengganti versi sekali per tenant per statement. Pindah tenant, bila
dilakukan lewat SQL administratif, memperbarui versi tenant lama dan baru. Versi dan
perubahan katalog commit/rollback bersama. Versi tidak bergantung pada DEL Redis
yang dapat hilang ketika jaringan terputus.

Sebelum lookup cache, query SQL membaca membership/tenant/pabrik aktif dan generasi
dari satu snapshot saat ini. Guard autentikasi juga tetap berjalan. Request yang
dimulai setelah commit memperoleh generasi baru; entri generasi lama tidak bisa
dipakai oleh request tersebut, sekalipun TTL-nya belum habis. Request yang sudah
membaca versi sebelum commit dapat menyelesaikan snapshot lamanya seperti pembacaan
database biasa. Data yang diisi bersamaan dengan perubahan tidak dapat menghidupkan
kembali key pada generasi baru.

Key mencakup hash environment/host/path database, tenant, pabrik, user, role yang
dibaca ulang, nama katalog, generasi, versi skema cache dan hash filter terurut.
Token, password koneksi dan teks pencarian tidak ditaruh dalam key. Katalog berlaku
untuk sintetis/resmi bersama; tidak ada filter kategori yang hasilnya dicampur.
Cache tidak dipakai untuk scope/hasil lain yang membutuhkan kunci kategori tersebut.

Envelope memuat hash key dan versi skema; hit juga memeriksa tenant pada item,
bentuk halaman, limit/offset dan jenis katalog. JSON rusak, scope salah atau payload
lebih dari 256 KiB dianggap miss, bukan dikembalikan ke pengguna. Respons error
database dan penolakan otorisasi tidak disimpan. Bentuk JSON API tetap sama; tanggal
yang berasal dari cache berupa string ISO seperti serialisasi respons biasa.

TTL 300 detik mengatur umur/resource entri, bukan izin menampilkan katalog lama
selama lima menit setelah perubahan. Keputusan toleransi stale untuk laporan dan
ringkasan tetap terbuka, sehingga kedua kategori itu belum dicache.

## Kegagalan dan penggabungan request

Request identik digabung per proses setelah pemeriksaan akses/versi. Maksimal 100
fill unik dicatat bersamaan; selebihnya memakai database biasa. Antar-instance,
`SET ... NX PX 2000` menandai fill selama dua detik. Instance lain menunggu paling
banyak lima percobaan berjarak 25 ms untuk memperoleh hasil; jika belum ada, memakai
database. Lock berakhir sendiri, sehingga pelepasan tidak dapat menghapus lock
milik filler lain. Ini mengurangi stampede, bukan janji satu query global ketika
pengisian sangat lambat atau Redis gagal.

Timeout berlaku per operasi koneksi/command Redis, bukan deadline seluruh request.
Retry pengisian lintas-instance dapat menambah beberapa round trip. Offline queue
dimatikan dan command tidak diretry; reconnect berjalan di latar dengan backoff.
Redis timeout/mati, SET gagal atau lock menggantung tidak mengganti data database
dengan salinan stale. Setelah Redis pulih, generasi PostgreSQL tetap diperiksa.

Log debug setiap 30 detik (`event=catalog_cache`) mencatat hit/miss, error, invalid,
coalesced, skipped, lock wait dan jumlah fill. `statistics()` tersedia internal.
Pantau memory/eviction di Redis/provider (misalnya INFO memory/stats bila diizinkan);
metrik server tersebut belum dipungut otomatis oleh API. Jangan mengaktifkan Redis
publik tanpa autentikasi atau menyimpan connection string pada laporan/Git.

## Profil sintetis dan indeks pencarian

`npm run perf:catalogs` memerlukan `PERF_DATABASE_URL` loopback dengan nama
`sobatnira_perf_*`, migrasi bisnis dan dukungan `pg_trgm` pada database disposable.
`PERF_CATALOG_ROWS` default 20000, rentang 1000–100000. Skrip menangkap SQL repository,
memeriksa kesetaraan pencarian literal `%`, `_`, `!`, lalu membandingkan `strpos`,
LIKE ber-escape dan kandidat GIN `lower(name) gin_trgm_ops`. Data, extension dan
index kandidat di-rollback; hasil ada di `.tmp/performance/catalog-query-profile.json`.

Hasil lima sampel hangat, satu koneksi, 20.000 pemasok sintetis:

| Operasi | Median |
| --- | ---: |
| Daftar/pencarian umum dengan strpos dan COUNT | 75,503 ms |
| Pencarian substring langka dengan strpos | 28,086 ms |
| Pencarian umum LIKE + GIN | 84,251 ms |
| Pencarian langka LIKE + GIN | 5,107 ms |
| INSERT 500 tanpa/dengan GIN | 49,378 / 45,543 ms |
| UPDATE waktu 500 tanpa/dengan GIN | 70,223 / 73,845 ms |
| Cache cold, termasuk koneksi awal | 103,146 ms |
| Cache warm, termasuk pemeriksaan akses/versi SQL | 6,094 ms |

Kandidat GIN berukuran 1.081.344 byte, membantu substring langka tetapi tidak
pencarian umum/karakter pendek. Selisih biaya tulis pada lima sampel ini tidak
membuktikan penghematan tulis atau biaya maintenance jangka panjang. Volume dan
frekuensi pencarian produksi belum diketahui, sehingga **pg_trgm dan perubahan
query LIKE tidak diterapkan ke aplikasi**. Query asli dipertahankan; cache menangani
pembacaan berulang, sementara GIN tetap kandidat bila pola produksi membenarkan.

Cache pada profil memakai fixture protokol TCP lokal, **bukan server Redis nyata**.
Hasil 6,094 ms bukan p95 HTTP atau estimasi latensi provider; belum termasuk guard
Auth/Flutter/jaringan. Data dan extension profil tidak dipasang ke database tim.

## Verifikasi dan penerapan

Tes unit memeriksa scope user/pabrik/tenant/role/filter, expiry, pengisian bersama,
payload rusak, DB error, cache nonaktif dan timeout command ioredis. Tes PostgreSQL
dengan HTTP dan fixture protokol memeriksa rollback, visibility sebelum commit dari
koneksi terpisah, update/insert/delete/truncate, pencabutan membership, TTL, Redis
terputus dan pemulihan. Ini belum menggantikan uji server/provider Redis nyata,
eviction, multi-replika dan beban produksi.

Urutan rilis: terapkan migrasi 025 dengan role migrasi yang biasa dipakai proyek,
verifikasi role runtime boleh membaca/menulis metadata versi, deploy API dengan
flag false, uji staging, lalu aktifkan flag. Migrasi menambahkan trigger pada dua
tabel; sediakan jendela DDL/lock dan periksa beban tulis di staging. Bila role migrasi
dan runtime berbeda, berikan hak minimum metadata secara privat; jangan memberi
akses tabel kepada anon/authenticated.

Rollback pertama: `CATALOG_CACHE_ENABLED=false` dan restart. Kode lama dapat berjalan
dengan tabel/trigger tambahan tetap ada; tidak perlu menghapus metadata saat rollback.
Jangan menonaktifkan trigger atau mengubah katalog di luar protokol invalidasi saat
cache aktif. Setelah restore/mengganti sumber database, kosongkan namespace cache
atau ganti versi key sebelum aktivasi kembali bila konsistensi snapshot diragukan.

Nomor 024 tetap milik `024_production_snapshot_lot_lookup.sql`. Versi eksperimen
commit `f894172` sempat memakai nomor 024 juga untuk cache. Bila versi eksperimen
itu sudah diterapkan, cocokkan checksum SQL cache dengan file 025 (normalisasi CRLF
seperti migrator), lalu ganti **nama catatan** `024_catalog_cache_versions.sql` pada
`sobatnira._migrations` menjadi `025_catalog_cache_versions.sql`. Jangan menjalankan
ulang DDL tabel/trigger atau mengubah catatan migrasi indeks snapshot. Database lokal
sintetis sudah direkonsiliasi dan migrator kembali diuji idempoten; belum ada
penerapan ke database tim/produksi pada pekerjaan ini.
