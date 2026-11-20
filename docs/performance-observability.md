# Metrik HTTP, query dan pool

Implementasi lokal mengumpulkan metrik tanpa menyimpan body, token, URL mentah,
parameter query SQL atau hasil OCR. Tidak ada endpoint metrik publik baru.

## HTTP

Middleware pada `createApplication()` mengukur waktu dari masuk aplikasi sampai
event response `finish`, dengan route pattern Express, misalnya `GET /.../:id`.
Parameter/UUID aktual dan query string tidak menjadi label. URL yang tidak cocok
masuk `<unmatched>`. Jenis method dibatasi dan label maksimal 256; selebihnya masuk
`<other-routes>`, sehingga input klien tidak menumbuhkan map tanpa batas.

Setiap label mencatat jumlah respons, error HTTP >=400, koneksi klien terputus,
ukuran body yang diketahui, respons tanpa ukuran diketahui, dan histogram durasi.
Event `close` sesudah `finish` tidak dihitung ulang. Respons HEAD/204/304 mempunyai
body nol. Stream tanpa Content-Length dicatat sebagai ukuran tidak diketahui;
ukuran tersebut tidak diasumsikan nol. Byte berasal dari header body, bukan ukuran
HTTP header/TLS atau keseluruhan traffic jaringan.

Pengukuran selesai di server, bukan waktu sampai UI selesai menampilkan hasil.
Preflight yang diselesaikan middleware CORS sebelum metrik tidak ikut dihitung.
Request yang tidak melewati `createApplication()` juga tidak mempunyai middleware
ini. Tidak ada correlation ID aksi Flutter, sehingga jumlah request per klik/aksi
masih memerlukan pengukuran klien yang terpisah.

## Query dan pool

Kedua pool mengukur waktu akuisisi, query langsung melalui `DatabaseService.query`
atau `Database.query`, serta keseluruhan transaksi dari koneksi diperoleh sampai
commit/rollback. Waktu query langsung tidak mencakup waktu menunggu pool; metrik
akuisisi memuat antrean serta pembukaan koneksi/TLS. Transaksi mempunyai hitungan
gagal, termasuk penolakan domain yang menyebabkan rollback, bukan hanya error SQL.

Statement yang dijalankan pada session/PoolClient di dalam transaksi tidak dihitung
lagi sebagai query langsung. Untuk rincian statement transaksi gunakan profiler
query/EXPLAIN dan fasilitas PostgreSQL yang sesuai. Tidak ada monkey-patch client
atau logging SQL/parameter. Query gagal/timeout tetap masuk histogram query langsung
dan counter error; transaksi gagal tetap masuk histogram transaksi.

Jumlah koneksi total/idle/waiting, total/maksimum waktu dan hitungan akuisisi dari
tahap pool tetap tersedia. Diagnostik lock wait, statistik tabel/index dan umur
transaksi ada pada [panduan kapasitas](database-capacity.md).

## Histogram dan log

Histogram memakai bucket tetap 1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000,
10000, 30000, 60000, 300000 ms dan overflow. Tidak menyimpan sampel individual.
`p50UpperBoundMs`, `p95UpperBoundMs`, `p99UpperBoundMs` adalah **batas atas bucket**,
bukan percentile presisi. Nilai null berarti belum ada sampel atau percentile
berada di bucket overflow; lihat count dan bucket terakhir untuk membedakannya.
Count bucket bukan kumulatif; totalnya sama dengan jumlah sampel.

`LOG_LEVEL=debug` menampilkan JSON setiap 30 detik:

| Event | Isi |
| --- | --- |
| `http_metrics` | Snapshot per route, durasi, error/abort dan byte yang diketahui |
| `database_pool` | Pool business/documents, akuisisi, query langsung dan transaksi |
| `ocr_queue` | Backlog/umur eligible, retry/lease dan statistik polling |
| `catalog_cache` | Hit/miss/error, penggabungan request dan fill katalog |

Counter kumulatif sejak proses hidup; restart mengulang dari nol. Sampling debug
bukan backend penyimpanan metrik atau alerting. `HttpMeasurements.snapshot()`,
`poolStatistics()` dan statistik queue/cache dapat dihubungkan ke kolektor internal.
Jangan menjadikan snapshot agregat seluruh pabrik sebagai endpoint owner biasa.

## Verifikasi dan pengukuran lanjutan

Tes memeriksa kuantil bucket, batas label, redaksi path/query/token, ukuran body
HTTP nyata, hitungan abort satu kali, serta hitungan query/transaksi gagal pada
PostgreSQL. Metrik belum mengukur overhead/p95 produksi atau menetapkan SLO.

Tahap berikutnya tetap memerlukan perangkat/build/jaringan yang dicatat untuk
klik Konfirmasi, cache dingin/hangat dengan Redis nyata, beban bersama, pool wait,
CPU/RAM dan lock wait. Profil lokal di dokumen laporan, foto, worker dan katalog
adalah baseline sintetis; target resource dan rencana replika mengikuti kapasitas
database/perangkat tim sebelum deployment.
