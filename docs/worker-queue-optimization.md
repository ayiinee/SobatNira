# Antrean OCR dan query review

Worker OCR tetap memproses satu pekerjaan per proses. Tidak ada kenaikan concurrency
Paddle, perubahan timeout/lease ekstraksi, jumlah percobaan atau aturan pembukuan.

## Polling dan penghentian

`DOCUMENT_POLL_MIN_MS` dan `DOCUMENT_POLL_MAX_MS` menerima integer 50–30000 ms,
dengan MAX minimal MIN. Default **500/500** mempertahankan jeda kosong sebelumnya.
Ketika pekerjaan ditemukan, worker menjadwalkan claim berikutnya dengan jeda 0 pada
putaran event loop berikutnya, setelah pekerjaan sebelumnya selesai. Tidak ada claim
otomatis yang tumpang tindih pada satu instance.

Jika kosong atau terjadi kegagalan, jeda berlipat hingga MAX; setelah pekerjaan
ditemukan, jeda idle di-reset ke MIN. Contoh opt-in **500/2000** menghasilkan jeda
500 → 1000 → 2000 → 2000 saat idle, mengurangi polling idle dari sekitar 2 menjadi
0,5 per detik setelah stabil, dengan tambahan keterlambatan deteksi hingga 2 detik.
Contoh tersebut belum diaktifkan sebagai default karena target latensi tim belum
ditentukan. Durasi query juga memengaruhi interval nyata.

Shutdown membatalkan timer berikutnya dan menunggu pekerjaan aktif. Setelah proses
benar-benar mati, protokol lease/reclaim yang sudah ada tetap berlaku. Instance
worker yang berbeda tetap memakai `FOR UPDATE SKIP LOCKED` dan claim token; hasil
worker yang kehilangan lease tidak boleh mengganti hasil pemilik baru.

## Metrik

Saat worker aktif, sampler independen setiap 30 detik membaca hanya status aktif
`QUEUED/PROCESSING`: jumlah queued/processing, lease kedaluwarsa, retry aktif dan
umur pekerjaan tertua yang sudah eligible. `oldestEligibleWaitMs: null` berarti tidak
ada pekerjaan eligible, bukan umur nol. Query memanfaatkan kelas status pada indeks
parsial antrean; pekerjaan terminal tidak perlu dihitung ulang pada tiap sampel.

Log debug `event=ocr_queue` juga memuat jumlah poll, poll kosong, error claim/loop
dan jeda idle saat ini. Error tersebut berbeda dari kegagalan ekstraksi: durasi OCR,
queue wait, percobaan dan hasil ekstraksi tetap tersedia pada log pekerjaan yang
sudah ada. Tidak ada nomor telepon, isi OCR, nama pemasok atau kredensial pada metrik.
Sampel gagal dilaporkan sebagai kegagalan sampling, bukan backlog nol. Sampling
tidak menahan jalur claim dan tidak saling tumpang tindih.

Tidak ada endpoint publik metrik baru. Gunakan `LOG_LEVEL=debug` untuk sampel ini
atau hubungkan `queueStatistics()`/statistik poller ke pengumpul metrik internal.
Pengukuran CPU/RAM/throughput Paddle dan sizing replika produksi tetap diperlukan.

## Query review: pilih halaman sebelum rincian

Query daftar review kini membuat CTE `page AS MATERIALIZED`. Status, pabrik, revisi,
membership aktif dan otorisasi bisnis diperiksa sebelum ORDER BY/LIMIT/OFFSET.
Pengambilan revisi, submission, inbound dan pengirim dilakukan setelah itu untuk
baris halaman. Urutan `created_at DESC,id`, kontrak page/page_size dan bentuk item
tetap sama. Semua pembacaan berada dalam satu statement/snapshot PostgreSQL.

Ini mengurangi pengambilan kolom/relasi yang akhirnya dibuang oleh pagination.
OFFSET tetap mempunyai biaya pada halaman jauh; perubahan ini tidak mengubah daftar
review menjadi cursor dan tidak mengklaim biaya konstan untuk semua halaman.

## Profil dan keputusan indeks

Dari `apps/api`, setelah build, jalankan `node scripts/profile-queues.cjs` dengan
`PERF_DATABASE_URL` loopback dan nama `sobatnira_perf_*`. Database disposable harus
memiliki migrasi bisnis dan OCR. `PERF_QUEUE_ROWS` antara 3000–100000, default 30000.
Fixture SQL sintetis mencakup dua pabrik (75%/25%), 30.000 dokumen/revisi/submission,
30.000 review task dan job: 10% queued, 10% processing (separuh lease kedaluwarsa),
sisanya completed; review 10% pending, 90% validated. Tidak membuat file storage.

Skrip membandingkan query lama dari commit `553beb0`, query repository baru dan
kandidat index `(status,created_at DESC,id)`. Ia memastikan baris dan urutan query
lama/baru identik. SQL claim/statistik ditangkap dari repository. Lima sampel hangat,
`EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` dan eksperimen INSERT/UPDATE 500 task
dicatat ke `.tmp/performance/queue-query-profile.json`. Semua data dan kandidat index
di-rollback. ANALYZE hanya dijalankan pada database disposable yang dijaga namanya.

Median operasi lokal pada 30.000 task:

| Operasi | Lama | Pilih halaman dahulu | Ditambah kandidat index |
| --- | ---: | ---: | ---: |
| Review pending, 20 pertama | 140,902 ms | 107,268 ms | 95,213 ms |
| Review validated, OFFSET 1980, 20 item | 532,469 ms | 82,918 ms | 74,162 ms |
| Claim job | 2,774 ms | 2,381 ms | 2,555 ms |
| Sampel antrean aktif | 16,334 ms | 16,826 ms | 17,865 ms |
| INSERT 500 task | 49,727 ms | 46,588 ms | 64,824 ms |
| UPDATE 500 waktu task | 70,713 ms | 67,674 ms | 80,993 ms |

Kandidat index berukuran **1.818.624 byte** dan **tidak dipakai** oleh planner pada
query review di pengukuran ini. Perbedaan kecil timing antarfase tidak membuktikan
manfaat index yang tidak dipakai, sementara biaya tulis meningkat. **Tidak ada
migrasi index tambahan.** Index claim, batch per kloter/status dan snapshot terbaru
yang sudah tersedia dipertahankan; tidak ditambah duplikat. Penurunan paling jelas
berasal dari query rincian yang dibatasi setelah pemilihan halaman, sekitar 6,4×
pada OFFSET tersebut, bukan dari index baru.

Sampel satu koneksi/satu mesin, urutan fase, cache hangat dan rollback tulis tidak
mewakili p95 HTTP, beban bersamaan, WAL/maintenance produksi atau semua distribusi
tenant. Ulangi dengan distribusi/backlog tim sebelum keputusan indeks berikutnya.

## Pengujian dan rollout

Tes timer memakai scheduler terkontrol: backoff berbatas, reset saat ada pekerjaan,
error dan shutdown yang menunggu pekerjaan tanpa rearm. Tes PostgreSQL memeriksa
backlog/lease kedaluwarsa, dua worker bersamaan merebut satu job, reclaim dan retry
akhir pada alur OCR → review → pembukuan yang sudah tersedia. Profil juga membandingkan
identitas/urutan hasil query lama dan baru.

```powershell
npm run build
node --test --test-concurrency=1 test/adaptive-poller.test.cjs test/document_flow.test.cjs
```

Tidak ada migrasi baru untuk tahap ini. Deploy kode dengan default 500/500 dahulu,
pantau queue wait dan database, lalu evaluasi MAX lebih besar di staging bersama
target latensi. Rollback kode mengembalikan interval 500 ms sebelumnya. Kebijakan
retensi job/payload dan concurrency Paddle tidak diubah oleh optimisasi polling.
