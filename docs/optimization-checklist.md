# Checklist optimisasi SobatNira

Terakhir ditinjau: **21 November 2026 (Asia/Jakarta)**.

Dokumen ini melacak pekerjaan backend, database, caching, foto dan retensi storage
dari audit awal serta implementasi bertahap. Status diperiksa terhadap kode workspace
dan hasil pengujian yang dicatat selama pengerjaan. Centang implementasi lokal tidak
berarti perubahan sudah di-commit, digabung, atau diterapkan ke database tim/produksi.

## Cara memperbarui

- `[x]` berarti butir tersebut selesai pada cakupan yang tertulis dan memiliki bukti.
- `[ ]` berarti belum selesai, termasuk pekerjaan parsial atau keputusan yang belum disepakati.
- Pertahankan ID tugas saat memindahkan urutan, agar referensi review tetap stabil.
- Setelah perubahan, perbarui centang, tanggal tinjauan, bukti, dan pekerjaan berikutnya.
- Setelah satu unit pekerjaan selesai dan diverifikasi, commit dengan Conventional Commits lalu push ke branch kerja di remote. Penggabungan ke main dan deployment mengikuti proses rilis tersendiri.
- Catat pengujian yang dilewati/gagal serta batas hasil pengukuran; jangan menggantinya dengan klaim selesai.
- Simpan kredensial, nota asli, identitas mitra dan dokumen internal di luar Git.

## Ringkasan tahap

| Tahap | Status saat ini | Sisa utama |
| --- | --- | --- |
| 1. Transaksi upload WhatsApp | Implementasi dan pengujian lokal selesai | Pengukuran latensi upload, rekonsiliasi, penerapan lingkungan tim |
| 2. Query dan pagination | Pagination kloter dan Flutter selesai: cursor, filter, ranking, badge, lazy loading dan refresh | Ringkasan, pagination rincian dan batas laporan selesai di bagian D |
| 3. Retensi storage | Inventaris dan simulasi lokal selesai; tanpa penghapusan sesuai keputusan pengguna | Review staging, metadata lifecycle dan keputusan masa simpan; worker hapus ditunda |
| 4. Optimisasi foto | Validasi bersama, preview/thumbnail dan unduh asli sesuai kebutuhan tersedia | Metadata turunan persisten, kualitas tulisan tangan/foto besar, peak RAM dan latensi perangkat |
| 5. Database dan kapasitas | Pool terkonfigurasi, metrik akuisisi/transaksi dan diagnostik tersedia; indeks lama dimanfaatkan | Profil antrean/review/pencarian, sizing produksi, beban/staging |
| 6. Caching | Cache katalog opt-in, generasi PostgreSQL, isolasi, penggabungan request dan fallback selesai lokal | Server Redis nyata, beban/staging; laporan belum dicache |
| 7. Verifikasi dan rilis | Tes lokal tahap 1–2 selesai | Uji Flutter, beban, staging dan rilis |

## A. Baseline dan observabilitas

- [x] **OBS-01** Audit kode upload, query, storage, Redis, pool dan worker; pisahkan temuan kode dari dugaan bottleneck produksi.
- [x] **OBS-02** Tambahkan `npm run perf:lots` untuk query repository kloter asli dengan data sintetis pada database lokal disposable.
- [x] **OBS-03** Rekam `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` untuk offset/cursor halaman awal dan jauh.
- [x] **OBS-04** Ukur 20.000 kloter sintetis, 50 item per halaman, lima sampel per query; simpan rencana eksekusi di `.tmp/performance/lots-query-profile.json`.
- [ ] **OBS-05** Profilkan laporan, daftar review, pencarian teks, saldo/reservasi dan pengambilan snapshot terbaru dengan kepadatan nota/batch realistis.
- [ ] **OBS-06** Ukur waktu dari klik Konfirmasi sampai hasil tampil dan jumlah request pada jaringan normal/lambat; catat build, perangkat, pabrik sintetis dan kondisi jaringan.
- [ ] **OBS-07** Tambahkan metrik HTTP/query p50/p95/p99, error, ukuran respons dan jumlah request per aksi.
- [ ] **OBS-08** Pantau waktu menunggu pool, koneksi aktif/idle/menunggu, durasi transaksi, lock wait dan timeout.
- [ ] **OBS-09** Ukur ukuran tabel/index, pertumbuhan JSON ekstraksi/revisi/audit, jumlah objek dan byte storage per kategori.
- [ ] **OBS-10** Tetapkan target performa dan anggaran resource berdasarkan baseline; verifikasi dengan beban bersamaan dan cache dingin/hangat.

## B. Transaksi upload dan konsistensi

- [x] **UPL-01** Pisahkan pemeriksaan awal, upload storage, dan transaksi pemasangan referensi; tidak ada transaksi database terbuka selama upload.
- [x] **UPL-02** Tambahkan manifest `media_uploads` melalui migrasi OCR `009_media_uploads.sql` agar percobaan upload dapat direkonsiliasi.
- [x] **UPL-03** Periksa ulang operator/pabrik, rate limit, duplikat dan revisi setelah upload sebelum pemasangan.
- [x] **UPL-04** Pasang media, submission, revisi, audit, manifest tertaut dan job OCR secara atomik.
- [x] **UPL-05** Pertahankan key deterministik, penulisan tanpa menimpa objek, replay idempoten dan alias foto duplikat.
- [x] **UPL-06** Uji kegagalan storage, rollback pemasangan, retry, pencabutan akses dan perpindahan pabrik saat upload.
- [x] **UPL-07** Uji PostgreSQL: kiriman bersamaan, pelepasan lock operator, alias foto dan perubahan revisi saat upload.
- [x] **UPL-08** Dokumentasikan urutan migrasi sebelum restart API/worker dan rollback kode yang mempertahankan tabel tambahan.
- [ ] **UPL-09** Ukur durasi transaksi dan latensi upload sebelum/sesudah pada storage serta beban yang representatif.
- [ ] **UPL-10** Uji gangguan proses dan hasil COMMIT yang tidak pasti bersama rekonsiliasi; pastikan objek yang sudah tertaut tidak terhapus.
- [ ] **UPL-11** Inventaris orphan lama yang belum memiliki manifest; jangan menganggap manifest mencakup seluruh objek historis.

Bukti: [implementasi intake](../apps/api/src/documents/intake.ts),
[migrasi manifest](../apps/api/migrations/ocr/009_media_uploads.sql),
[tes staged upload](../apps/api/test/staged-photo.test.cjs),
[petunjuk deployment tahap 1](ai/README.md#optimisasi-upload-whatsapp-tahap-1).

## C. Pagination kloter dan Flutter

- [x] **PAG-01** Tambahkan mode API opt-in `pagination=cursor`, `after` dan `nextCursor` tanpa `COUNT(*)` pada jalur cursor.
- [x] **PAG-02** Pertahankan respons offset lama dan total lengkap untuk klien yang belum bermigrasi.
- [x] **PAG-03** Pertahankan urutan `received_at DESC, id ASC` serta presisi mikrodetik pada cursor.
- [x] **PAG-04** Sesuaikan kondisi batas tanggal agar indeks `lots_factory_received_idx` dapat mencari langsung ke halaman jauh.
- [x] **PAG-05** Uji validasi cursor, timestamp sama/mikrodetik, akhir halaman, hasil kosong dan isolasi pabrik melalui API.
- [x] **PAG-06** Lengkapi kontrak filter status dan pencarian server sesuai perilaku UI, termasuk normalisasi kode/ID dan pengelompokan tanggal.
- [x] **PAG-06A** Tambahkan filter server `status=open/closed` berdasarkan penutupan aktif; dukung cursor dan offset, termasuk pembukaan kembali kloter.
- [x] **PAG-06B** Tambahkan pencarian opsional `searchMode=normalized` untuk kode/UUID; pertahankan pencarian lama dan substring pemasok.
- [x] **PAG-06C** Selesaikan ranking saran exact/prefix/substring dan kontrak pengelompokan hari/zona waktu sebelum migrasi UI.
- [x] **PAG-07** Sediakan hitungan/badge dan ringkasan lengkap dari server; jangan menghitung total seluruh pabrik dari halaman yang baru dimuat.
- [x] **PAG-07A** Sediakan `GET /lots/counts` dengan `{ total, open, closed }` untuk seluruh filter pencarian/tanggal/pemasok/kategori; tanpa cursor, limit atau filter status.
- [x] **PAG-07B** Hubungkan badge Flutter ke counts dan pastikan kebutuhan ringkasan Beranda tidak bergantung pada halaman kloter parsial.
- [x] **PAG-08** Hubungkan client Flutter ke cursor dan lazy loading; hentikan loop yang mengambil seluruh halaman pada refresh.
- [x] **PAG-09** Reset cursor saat filter/pabrik/kategori sintetis berubah; cegah respons lama menimpa hasil baru dan permintaan halaman ganda.
- [x] **PAG-10** Pertahankan posisi/hasil halaman saat memuat berikutnya; sediakan status memuat, error, retry dan akhir daftar.
- [x] **PAG-11** Refresh data yang terdampak setelah validasi, koreksi, transfer dan penutupan tanpa mengunduh ulang seluruh daftar.
- [x] **PAG-12** Uji Flutter hingga API: pencarian, status, tanggal, badge, pindah pabrik, pagination dan perubahan data selama penelusuran.

Bukti: [repository kloter](../apps/api/src/lots/lots.repository.ts),
[validasi query](../apps/api/src/production/production.dto.ts),
[tes HTTP](../apps/api/test/integration/production-database.test.cjs),
[kontrak cursor dan baseline](backend-production-basics.md#pagination-dan-ringkasan-kloter).

Bagian C selesai pada implementasi lokal. Beranda, daftar Kloter dan pilihan kloter
Biaya Ops menggunakan pager terpisah. Badge memakai counts lengkap; total berat dan
margin tetap dari agregat laporan seluruh filter. Refresh mempertahankan kedalaman halaman yang
sudah dibuka, bukan menelusuri seluruh data pabrik. Hari dikelompokkan dalam zona
waktu perangkat, dengan batas hari dikirim ke API sebagai UTC. Satu hari dapat
berlanjut ke halaman berikutnya; header menyebut jumlah yang dimuat selama daftar
belum lengkap. Detail dan langkah menjalankan fixture ada pada kontrak di atas.

Bukti Flutter: [pager](../apps/mobile/lib/features/kloter/connected_lot_pager.dart),
[daftar](../apps/mobile/lib/features/kloter/kloter_list_page.dart),
[tes state/widget](../apps/mobile/test/features/kloter/lot_pagination_test.dart),
[tes Flutter-NestJS-PostgreSQL](../apps/mobile/test/features/kloter/lot_pagination_backend_test.dart).
Pengujian lokal mencakup 65 kloter dalam tiga halaman, tanggal, ranking di luar
halaman awal, badge, scope lain, pembukaan kembali dan refresh setelah penambahan.
Pengujian widget mencakup race respons, ketuk ganda load-more, retry cursor, posisi
scroll, pergantian pabrik/kategori dan navigasi detail. Penerapan ke lingkungan tim
atau produksi tetap merupakan pekerjaan rilis, bukan bagian centang implementasi ini.


## D. Laporan dan ukuran respons

- [x] **RPT-01** Ukur query laporan dengan periode, jumlah kloter, batch, grade dan revisi yang representatif.
- [x] **RPT-02** Pisahkan ringkasan/agregat dari rincian agar Beranda tidak memerlukan seluruh isi laporan.
- [x] **RPT-03** Tetapkan batas periode, jumlah baris dan ukuran respons; dokumentasikan error serta arahan untuk ekspor besar.
- [x] **RPT-04** Tambahkan pagination rincian dan arahkan laporan besar ke jalur ekspor asinkron yang sudah tersedia.
- [x] **RPT-05** Pertahankan konsistensi snapshot, periode penerimaan kloter, angka presisi dan aturan biaya satu kali per kloter.
- [x] **RPT-06** Uji koreksi aktif/disahkan/dibuang, margin negatif dan isolasi pabrik antara detail, Beranda, laporan dan PDF/XLSX.
- [x] **RPT-07** Verifikasi pembatasan baru tidak memotong laporan secara diam-diam atau menghasilkan total dari data parsial.

Lihat [kontrak dan baseline laporan](backend-report-optimization.md). Endpoint lengkap/laba/rekap dibatasi 100 kloter dan respons 5 MiB, rincian 1000 batch per kloter; interval eksplisit maksimal 366 hari. Summary dan halaman mempertahankan total seluruh filter. Ekspor owner memakai worker yang sudah tersedia (maksimal 500 kloter), dengan kontrol Flutter baru.

Profil sintetis 30 kloter, 120 batch/grade dan 150 snapshot: median lengkap 65,591 ms / 66.708 byte; summary 11,898 ms / 541 byte; halaman 20 kloter 78,479 ms / 44.775 byte. Lima sampel hangat lokal, belum p95 HTTP atau beban produksi. Build dan 10 tes laporan/integrasi terakhir lulus tanpa skip.

## E. Database, indexing dan pool

- [x] **DB-01** Verifikasi indeks kloter serta snapshot terbaru sudah tersedia; hindari menambahkan indeks duplikat.
- [x] **DB-02** Buktikan query cursor memakai indeks kloter yang tersedia, tanpa migrasi indeks tambahan.
- [ ] **DB-03** Evaluasi composite/partial index untuk batch sah, laporan, antrean review dan claim job berdasarkan rencana query serta selektivitas.
- [x] **DB-03A** Profil lokal review/claim/statistik pada 30.000 job/task dua pabrik; indeks claim lama dipakai, kandidat index review tidak dipakai dan tidak diterapkan.
- [x] **DB-04** Profil pencarian `strpos(lower(...))`; evaluasi perubahan query dan `pg_trgm` hanya bila pengukuran membenarkan.
- [ ] **DB-05** Ukur dampak setiap kandidat indeks pada baca, INSERT/UPDATE, ukuran index dan pemeliharaan sebelum membuat migrasi.
- [x] **DB-05A** Ukur kandidat review pada baca dan INSERT/UPDATE 500 task serta ukuran 1.818.624 byte; tolak kandidat yang tidak digunakan planner. Pemeliharaan/beban produksi tetap belum diukur.
- [ ] **DB-06** Tinjau biaya `COUNT(*)`, deep OFFSET, proyeksi kolom dan agregasi JSON; perbaiki hanya jalur yang terbukti mahal.
- [x] **DB-06A** Ambil rincian review sesudah halaman terotorisasi dipilih; verifikasi hasil identik dan profil OFFSET 1980 turun dari 532,469 menjadi 82,918 ms pada fixture lokal.
- [ ] **DB-07** Tetapkan anggaran koneksi gabungan pool bisnis, OCR, worker dan seluruh replika sesuai kapasitas database.
- [x] **DB-08** Jadikan batas pool/timeout/idle terkonfigurasi dan konsisten; ukur waktu menunggu koneksi sebelum menaikkan batas.
- [ ] **DB-09** Tinjau statistik planner, autovacuum, bloat dan indeks tidak terpakai menggunakan lingkungan representatif.
- [ ] **DB-10** Uji migrasi, konkurensi dan rollback strategi indeks/pool di staging sebelum penerapan produksi.

Bukti pool: [konfigurasi, anggaran dan rollback](database-capacity.md),
[instrumentasi](../apps/api/src/database/pool.ts),
[diagnostik SELECT](../apps/api/scripts/database-diagnostics.sql),
[tes pool PostgreSQL](../apps/api/test/integration/database-pool.test.cjs).
Dua pool kini eksplisit 5+5 per proses; waktu akuisisi dan durasi transaksi dicatat,
termasuk log debug tiap 30 detik. Tes antrean pool satu koneksi, rollback, timeout
server dan pemulihan lulus pada kedua jalur. Diagnostik lokal membaca 47 tabel/131
index; ini bukan penilaian kapasitas atau bloat produksi. DB-07 tetap terbuka sampai
jumlah replika dan kapasitas provider dikonfirmasi; DB-03/04/05/06/09/10 belum
dianggap selesai oleh perubahan pool.

## F. Retensi storage dan rekonsiliasi

Keputusan pengguna, 21 November 2026: **simulasi cleanup saja; belum menghapus otomatis**. Foto asli dan seluruh revisi historis tetap dilindungi. Ambang umur kandidat simulasi adalah parameter investigasi, bukan masa simpan yang disepakati. RET-11 sampai RET-16 yang mengaktifkan penghapusan ditunda sampai kebijakan disetujui.

### Keputusan kebijakan yang masih diperlukan

- [ ] **RET-01** Sepakati masa simpan foto bukti asli, revisi historis dan pengecualian untuk kebutuhan audit/sengketa.
- [ ] **RET-02** Sepakati masa tunggu upload sementara dan orphan, serta cara membedakannya dari upload aktif.
- [ ] **RET-03** Sepakati masa berlaku ekspor, kemampuan membuat ulang dari snapshot dan perilaku unduh setelah kedaluwarsa.
- [ ] **RET-04** Sepakati retensi thumbnail/preview, fixture/demo, log, payload OCR dan metadata idempotensi; jangan menghapus riwayat yang masih dibutuhkan retry/audit.
- [ ] **RET-05** Catat keputusan dan pemiliknya pada register tim sebelum mengaktifkan penghapusan otomatis.

Rentang **24–72 jam** untuk upload sementara, **7 hari** untuk orphan, serta **30 hari**
untuk ekspor pada audit awal hanya usulan pembahasan, belum kebijakan yang disetujui.
Foto yang bukan revisi aktif tetap dapat menjadi bukti historis yang wajib dipertahankan.

### Implementasi

- [x] **RET-06** Sediakan manifest upload WhatsApp dan indeks parsial untuk kandidat belum tertaut; ini baru fondasi rekonsiliasi.
- [x] **RET-07** Inventaris seluruh jalur: `tenants/.../evidence/...`, `originals/`, `reports/`, turunan gambar dan storage lokal development.
- [ ] **RET-08** Simpan kategori objek, ukuran/hash, waktu, kebijakan/versi, status lifecycle dan referensi pemilik yang diperlukan.
- [x] **RET-09** Buat mode simulasi yang melaporkan kandidat, alasan dan estimasi byte tanpa menghapus objek.
- [x] **RET-10** Periksa semua referensi: dokumen/revisi historis, pengesahan, submission, job aktif, artefak dan pengiriman laporan.
- [ ] **RET-11** Terapkan mark-and-sweep: tandai kandidat, tunggu masa aman, lalu periksa ulang referensi sebelum hapus.
- [ ] **RET-12** Cegah race antara pemasangan referensi/upload dan cleanup menggunakan protokol koordinasi yang diuji.
- [ ] **RET-13** Implementasikan worker per batch dengan status, retry idempoten, batas concurrency dan audit hasil penghapusan.
- [ ] **RET-14** Uji kegagalan parsial: R2 gagal, database gagal, timeout, proses mati dan hasil COMMIT tidak pasti.
- [ ] **RET-15** Pisahkan prefix/bucket fixture dan objek sementara dari bukti produksi; rencanakan kompatibilitas objek lama.
- [ ] **RET-16** Tinjau lifecycle R2 per prefix dan incomplete multipart; terapkan hanya untuk kelas objek yang aman kedaluwarsa.
- [ ] **RET-17** Jalankan simulasi pada inventaris staging dan review kandidat sebelum mengaktifkan penghapusan sesuai keputusan tim.

Bukti simulasi: [CLI dan batas operasional](storage-audit.md), [klasifikasi/referensi](../apps/api/src/storage/storage-audit.ts), [tes PostgreSQL](../apps/api/test/integration/storage-audit-database.test.cjs). Empat tes unit dan satu tes database lulus; CLI lokal pada database disposable menginventaris satu objek sintetis 27 byte sebagai kandidat investigasi, dengan `dryRun: true`, `deletionAllowed: false`. Prefix asing, waktu tidak pasti, seluruh media/evidence dan seluruh job ekspor dilindungi. Belum memindai bucket staging/produksi. RET-08 tetap parsial: laporan inventaris tersedia, registry lifecycle/hash terpadu belum ada.

Lifecycle bucket tidak mengetahui referensi database. Penghapusan bukti tertaut
memerlukan keputusan aplikasi, bukan hanya umur objek.

## G. Optimisasi foto

- [x] **IMG-01** Seragamkan validasi signature, MIME, decode, dimensi, jumlah frame dan batas byte/piksel sebelum penyimpanan permanen.
- [x] **IMG-02** Pertahankan sumber asli sesuai retensi; gunakan varian terpisah untuk preview dan thumbnail.
- [x] **IMG-03** Tetapkan ukuran/format/kualitas berdasarkan nota sintetis; jangan mengganti asli dengan kompresi tanpa pembuktian keterbacaan.
- [ ] **IMG-04** Hilangkan metadata lokasi pada varian tampilan dan simpan hash, ukuran, dimensi serta versi transformasinya.
- [x] **IMG-05** Pertahankan hubungan koordinat evidence dengan gambar asli saat resize/rotasi; uji overlay dan orientasi.
- [x] **IMG-06** Layani thumbnail/preview melalui otorisasi tenant/pabrik yang sama dan unduh asli hanya ketika dibutuhkan.
- [x] **IMG-07** Batasi concurrency transformasi dan penggunaan memori pada upload/baca; evaluasi streaming tanpa melemahkan verifikasi integritas.
- [ ] **IMG-08** Ukur byte asli/turunan, waktu transformasi, RAM, latensi tampilan dan penghematan transfer/storage.
- [ ] **IMG-09** Uji angka kecil, tulisan tangan, tanggal, foto buram/terpotong, JPEG/PNG/WebP yang didukung dan file rusak.
- [x] **IMG-10** Evaluasi dedup fisik per tenant/pabrik dengan referensi yang aman; bedakan file identik dari transaksi bisnis identik.

Bukti: [kontrak varian, resource dan profil foto](photo-optimization.md).
Validasi HTTP WhatsApp kini menggunakan decoder yang sama dengan bukti penerimaan;
format WhatsApp tetap JPEG/PNG sesuai kontrak AI. Preview WebP lossless maksimal 2048,
thumbnail 320, sumber asli tetap tersedia. Flutter Pekerjaan meminta preview dan
mengunduh asli saat tombol ditekan; bbox mempertahankan sumbu piksel mentah.
Satu slot aktif/empat antrean membatasi decode dan baca/transformasi per proses,
dengan batas piksel/byte serta timeout native; ini bukan batas RAM keras seluruh HTTP.
Empat fixture menghasilkan preview 31.346 dari 125.388 byte (sekitar 75% lebih kecil)
dengan piksel identik pada fixture tanpa resize. Belum ada varian tersimpan di R2,
jadi belum ada penghematan storage/R2 egress. IMG-04 dan IMG-08 masih parsial;
IMG-09 menunggu perluasan fixture tulisan tangan/buram/terpotong.

## H. Worker dan antrean OCR

- [x] **WRK-01** Pantau panjang antrean, umur job tertua, waktu tunggu, durasi OCR, retry dan kegagalan akhir.
- [ ] **WRK-02** Ukur kapasitas CPU/RAM Paddle serta throughput worker sebelum mengubah concurrency atau jumlah replika.
- [ ] **WRK-03** Terapkan concurrency terbatas dan backpressure agar upload/job tidak menghabiskan resource layanan.
- [x] **WRK-04** Evaluasi jeda polling adaptif saat kosong tanpa memperburuk latensi penerimaan pekerjaan.
- [ ] **WRK-05** Uji lease, reclaim, timeout, penghentian proses dan retry agar tidak menggandakan hasil atau kehilangan pekerjaan.
- [x] **WRK-06** Profil claim query dan evaluasi indeks antrean menggunakan backlog sintetis realistis.

Bukti: [worker, query review dan keputusan indeks](worker-queue-optimization.md).
Worker tetap serial; default idle 500/500 ms mempertahankan latensi polling lama.
Backoff MAX lebih besar tersedia sebagai opt-in setelah toleransi latensi diuji;
contoh 500/2000 belum diaktifkan. Metrik antrean dipisahkan dari claim dan tidak
menghitung ulang seluruh job terminal. Tes timer/shutdown, dua worker atas satu
lease kedaluwarsa, reclaim dan retry lulus. WRK-02/03/05 tetap parsial: belum ada
benchmark CPU/RAM Paddle, uji tekanan upload gabungan atau penghentian paksa proses
di staging. Tidak ada concurrency Paddle/worker atau kebijakan retry yang diubah.

## I. Redis dan caching

- [ ] **CAC-01** Pilih endpoint dari pengukuran biaya/frekuensi; sepakati toleransi data lama tiap kategori.
- [x] **CAC-01A** Pilih dua daftar katalog dari profil 20.000 pemasok; gunakan invalidasi generasi pada commit, tanpa mengizinkan TTL sebagai jendela stale. Frekuensi produksi dan toleransi laporan masih terbuka.
- [x] **CAC-02** Implementasikan cache-aside untuk katalog/ringkasan yang dipilih dengan TTL terkonfigurasi.
- [x] **CAC-03** Gunakan key berisi tenant, pabrik, filter/periode, sintetis/resmi, versi dan cakupan akses bila hasil berbeda.
- [x] **CAC-04** Periksa otorisasi sebelum cache dikembalikan; pencabutan membership tetap berlaku pada request berikutnya.
- [ ] **CAC-05** Invalidasi setelah commit perubahan katalog, pengesahan, koreksi, transfer, biaya dan penutupan kloter.
- [x] **CAC-05A** Generasi katalog berubah atomik dengan INSERT/UPDATE/DELETE/TRUNCATE dan rollback bersama transaksi; operasi produksi tetap uncached, sehingga invalidasi ringkasannya belum diimplementasikan.
- [x] **CAC-06** Tangani kegagalan/race invalidasi antar-replika; TTL menjadi batas cadangan, bukan satu-satunya jaminan konsistensi.
- [x] **CAC-07** Gabungkan request identik saat cache kosong dan cegah lonjakan pengisian ulang bersamaan.
- [ ] **CAC-08** Sediakan fallback database dengan timeout Redis terbatas dan pantau hit/miss, eviction, error serta memori.
- [x] **CAC-08A** Fallback database, timeout per command, log hit/miss/error/invalid/coalesced tersedia; eviction/memory server Redis tetap dipantau melalui provider, belum dipungut API.
- [x] **CAC-09** Pertahankan pembacaan keadaan resmi untuk validasi stok, reservasi dan penutupan dalam transaksi database.
- [ ] **CAC-10** Uji isolasi pabrik/role, invalidasi koreksi, cache kedaluwarsa, Redis mati dan pemulihan.
- [x] **CAC-10A** Uji katalog dengan unit dan HTTP/PostgreSQL serta fixture protokol TCP ioredis: scope, commit/rollback, TTL, timeout, outage/reconnect dan pengisian antar-instance. Server Redis nyata/multi-replika staging belum diuji.

Kontrak dan bukti ada pada [cache katalog](catalog-cache.md). Migrasi bisnis 024
menambahkan metadata generasi dan trigger statement-level. Default flag false;
TTL katalog 300 detik mengatur umur entri, bukan stale setelah perubahan commit.
Profil sintetis: katalog 75,503 ms, cold cache 103,146 ms, warm 6,094 ms (Redis fixture
protokol lokal, bukan p95 provider). GIN 1.081.344 byte membantu substring langka
28,086 → 5,107 ms, tetapi tidak pencarian umum; belum diterapkan tanpa pola produksi.
Cache Beranda/laporan dan toleransi stalenya tetap terbuka. Caching tidak menjadi
pengganti pembacaan resmi pada transaksi stok/pengesahan.

## J. Bukti pengujian dan penerapan

- [x] **QA-01** Build TypeScript tahap 1–2 lulus.
- [x] **QA-02** Tahap upload: 84 tes lulus tanpa skip dengan PostgreSQL sintetis terisolasi dan runner berurutan.
- [x] **QA-03** Tahap cursor: 86 tes backend/integrasi lulus tanpa skip, termasuk tes HTTP kloter.
- [x] **QA-03A** Tahap filter/counts: build dan 87 tes backend/integrasi lulus tanpa skip pada PostgreSQL sintetis; mencakup penutupan/pembukaan kembali, pemisahan sintetis/resmi, filter, akses anonim dan pencabutan membership.
- [x] **QA-04** Dokumentasikan keterbatasan baseline: satu koneksi, lima sampel query hangat, belum HTTP/Auth, beban bersamaan atau nota padat.
- [ ] **QA-05** Jalankan `flutter analyze` dan `flutter test` setelah integrasi pagination/preview; uji aplikasi hingga API terkait.
- [x] **QA-05A** Pagination: analyzer Flutter bersih, suite standar 131 tes lulus (3 tes fixture dilewati); pengujian terarah dependensi Beranda/Biaya Ops lulus, lalu 22 tes regresi lulus setelah perbaikan terakhir, termasuk posisi scroll dan layar 320 px dengan teks 2x. Tes end-to-end pagination dijalankan terpisah dan lulus dengan PostgreSQL sintetis.
- [x] **QA-04A** Tahap laporan/storage/pool: 100 tes backend/integrasi lulus tanpa skip pada PostgreSQL sintetis. Sesudah penambahan sampling metrik, build dan 8 tes pool/storage terarah kembali lulus. Tidak ada uji bucket produksi atau deployment.
- [x] **QA-05B** Laporan: analyzer bersih dan suite Flutter 136 tes lulus, 3 tes fixture dilewati (runner berurutan). Build API serta regresi PostgreSQL summary/page, koreksi, PDF/XLSX dan batas 101 kloter lulus; detail bukti ada di bagian D.
- [x] **QA-05C** Foto: build dan 107 tes backend/integrasi lulus tanpa skip; analyzer Flutter bersih dan 5 tes Pekerjaan/varian lulus. Mencakup foto rusak, WebP animasi/APNG, hash, orientasi/bbox, antrean transformasi, akses pabrik dan pembukaan asli setelah preview gagal. Suite Flutter penuh belum diulang setelah tahap foto; hasil 136 tes di atas berasal dari tahap laporan.
- [x] **QA-05D** Worker/review: build dan 13 tes timer/alur OCR PostgreSQL lulus tanpa skip. Profiler 30.000 task/job memverifikasi hasil query lama/baru identik dan merekam biaya baca/tulis kandidat index yang akhirnya ditolak.
- [x] **QA-05E** Katalog/cache: migrasi 024 diterapkan pada database sintetis, build dan suite 117 tes backend/integrasi lulus tanpa skip. Redis diuji melalui fixture protokol lokal, belum server/provider nyata; flag cache tetap nonaktif secara default.
- [ ] **QA-06** Jalankan tes FastAPI dari `apps/ai` dengan `uv run --locked python -m unittest` bila kontrak/pemrosesan AI berubah.
- [ ] **QA-07** Uji satu skenario sintetis dari foto → OCR → revisi → pengesahan → stok → laporan/PDF; pastikan angka dan status konsisten.
- [ ] **QA-08** Uji R2 nyata dengan fixture sintetis terpisah; catat dan bersihkan hanya objek fixture yang dibuat tes.
- [ ] **QA-09** Uji beban dan kegagalan gabungan serta bandingkan p95, RAM, koneksi, ukuran respons dan byte storage.
- [ ] **QA-10** Review diff, commit dan PR; sertakan perubahan kontrak, bukti, keterbatasan serta rencana rollback.
- [ ] **QA-11** Terapkan migrasi manifest ke lingkungan tim/staging sebelum kode upload baru, lalu smoke test dan pantau metrik.
- [ ] **QA-12** Terapkan perubahan ke produksi melalui proses rilis tim; catat versi, tanggal, hasil dan rollback bila diperlukan.

Perintah suite terakhir yang lulus, dari `apps/api` dengan database khusus sintetis:

```powershell
npm.cmd run build
node --test --test-concurrency=1 test/*.test.cjs test/integration/production-database.test.cjs
```

Pada percobaan sebelumnya runner sandbox terhalang `spawn EPERM`; eksekusi yang
diizinkan di luar sandbox berhasil. Satu tes Auth pernah menerima 503 saat suite
paralel dan lulus pada pengulangan berurutan. Angka di atas adalah hasil yang sudah
dicatat, bukan hasil menjalankan ulang tes saat memperbarui checklist.

## Review berikutnya

### Riwayat commit implementasi

Branch kerja: `perf/api-staged-photo-upload`.

| Tanggal | Commit | Cakupan |
| --- | --- | --- |
| 20 November 2026 | `596a0ac` | Transaksi upload foto, manifest, migrasi dan tes regresi |
| 20 November 2026 | `c490482` | Cursor API, counts, ranking saran, pager Flutter, profiler dan tes integrasi |
| 21 November 2026 | `eddeab9` | Ringkasan laporan, batas respons, rincian per halaman, jalur ekspor Flutter dan profil sintetis |
| 21 November 2026 | `b7911a9` | Inventaris dan simulasi cleanup tanpa penghapusan |
| 21 November 2026 | `0e11c3f` | Konfigurasi pool, metrik akuisisi/transaksi dan diagnostik database |
| 21 November 2026 | `553beb0` | Validasi bersama dan varian foto privat, overlay serta pembukaan asli di Flutter |
| 21 November 2026 | `5470202` | Query review sesudah pagination, metrik antrean dan opsi polling adaptif |

Riwayat ini mencatat commit lokal. Status sinkronisasi remote dapat diperiksa dengan
`git status -sb`; commit tidak berarti perubahan sudah digabung ke main atau dirilis.

### Urutan lanjutan

- [x] **NEXT-01** Selesaikan kontrak filter status dan hitungan lengkap, lalu migrasikan Flutter ke cursor (PAG-06 sampai PAG-12).
- [x] **NEXT-02** Profil dan batasi laporan (OBS-05, RPT-01 sampai RPT-07) sebelum menentukan indeks tambahan.
- [ ] **NEXT-03** Putuskan kebijakan retensi dan buat inventaris/simulasi cleanup sebelum penghapusan diaktifkan (RET-01 sampai RET-17).
- [ ] **NEXT-04** Lanjutkan preview foto, kapasitas worker/pool dan cache berdasarkan hasil pengukuran.

Panduan tugas kloter/loading/seeder/OCR yang diberikan pengguna menjadi konteks
verifikasi; checklist ini tidak menandai seluruh pekerjaan produk di panduan itu
sebagai telah diimplementasikan. Keputusan domain yang masih terbuka mengikuti
register internal tim, bukan ditetapkan oleh dokumen optimisasi ini.
