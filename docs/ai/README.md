# Menjalankan intake dan review nota

Skema JSON dan contoh sintetis tersedia di [schemas](schemas/) dan [examples](examples/). Status pengujian tercatat di [log implementasi](IMPLEMENTATION_LOG.md). PRD dan register keputusan tim disimpan secara privat di `docs/internal/ai/`.

Lihat [hasil Implementation Pack](IMPLEMENTATION_PROGRESS.md) untuk status terkini dan [kontrak capability owner](CAPABILITY_API.md) untuk membaca data resmi melalui NestJS.

## Instalasi bersama

Untuk uji penerimaan tim, gunakan Flutter **3.44.6** (Dart **3.12.2**), Chrome, Node.js **24.14.1** (npm **11.11.0**), Python **3.13.18** x64, uv **0.13.8**, dan PostgreSQL **18.6**. Samakan zona waktu browser ke **Asia/Jakarta** karena tampilan tanggal dan filter menggunakan zona waktu perangkat. Dari clone bersih, checkout SHA yang disetujui tim, lalu jalankan perintah per direktori.

| Direktori | Perintah |
| --- | --- |
| `apps/api` | `npm ci` dan `npm run build` |
| `apps/ai` | `uv sync --locked --extra paddle --python 3.13.18` |
| `apps/mobile` | `flutter pub get --enforce-lockfile` |

Panggilan pertama PaddleOCR mengunduh model. Gunakan `PADDLE_PDX_CACHE_HOME` untuk memilih direktori cache. Di PowerShell gunakan `npm.cmd` jika eksekusi `npm.ps1` diblokir.

## Mode lokal sintetis

1. Mulai dari `git clone https://github.com/ayiinee/SobatNira.git`, lalu `git checkout --detach <SHA-acuan>` di direktori clone. Simpan hasil `git rev-parse HEAD` dan pastikan `git status --short` kosong. Jalankan [instalasi bersama](#instalasi-bersama). Siapkan PostgreSQL lokal. Jika memakai Docker, jalankan `docker run` sekali dan buat database baru untuk setiap putaran. Untuk PostgreSQL yang sudah tersedia, gunakan `createdb` atau klien SQL untuk membuat database kosong yang setara.

   ```sh
   docker run --name sobatnira-local-db -e POSTGRES_PASSWORD=sobatnira-local -p 127.0.0.1:55437:5432 -d postgres:18.6
   docker exec sobatnira-local-db createdb -U postgres sobatnira_accept_a
   docker exec sobatnira-local-db createdb -U postgres sobatnira_accept_b
   ```

   Mulai ulang kontainer dengan `docker start sobatnira-local-db` bila sebelumnya dihentikan. Untuk putaran berikutnya gunakan nama database baru. Pertahankan database demo tim dan data uji terdahulu.

2. Dari `apps/mobile`, buat build dari entry point utama dengan satu origin lokal.

   ```sh
   flutter build web --no-web-resources-cdn -t lib/main.dart --dart-define=SOBATNIRA_MODE=local --dart-define=API_BASE_URL=http://127.0.0.1:8000 --dart-define=SUPABASE_URL=http://127.0.0.1:8000 --dart-define=SUPABASE_PUBLISHABLE_KEY=local-synthetic-publishable
   ```

3. Dari `apps/api`, jalankan perintah berikut dengan database A. Pada checkout B gunakan `sobatnira_accept_b` setelah proses checkout A dihentikan. Di Bash gunakan `export LOCAL_DATABASE_URL='…'` dan `npm`.

   ```powershell
   $env:LOCAL_DATABASE_URL = 'postgres://postgres:sobatnira-local@127.0.0.1:55437/sobatnira_accept_a'
   npm.cmd run local:stack -- --web --acceptance
   ```

   Buka `http://127.0.0.1:8000/` di profil browser bersih. Alamat ini menyajikan Flutter beserta CanvasKit lokal, NestJS, dan login sintetis. Bootstrap menerapkan migrasi dengan urutan produksi kemudian OCR (`sobatnira_local`), menyiapkan akun serta dua kloter uji, dan menjalankan worker NestJS serta FastAPI OCR internal (port loopback 8001). `--acceptance` memakai empat PNG sintetis dari [`apps/ai/fixtures/acceptance`](../../apps/ai/fixtures/acceptance) sehingga input OCR identik walaupun font sistem berbeda. Foto dibuat dengan `apps/ai/synthetic_notes.py`. Adapter simulasi memanggil PaddleOCR CPU dan menyimpan salinan privat di `.tmp/local-ai/media`. Tunggu terminal menampilkan tiga tugas siap diproses.

   Gateway preview membatasi koneksi browser dan pemuatan font ke origin lokal. Build di loopback memakai aset font bawaan, termasuk Roboto fallback untuk Flutter Web 3.44.6.

4. Masuk dengan `admin@example.invalid` / `sobatnira-demo`, lalu buka **Pengaturan → Pekerjaan** di **Pabrik Demo**. Gunakan ID tugas dan kode kloter yang dicetak terminal.

   - Buka **Nota Kedatangan Truk**, periksa foto dan riwayat, pilih **Validasi revisi ini**, pilih kloter `OCR-A-UJI`, lalu pilih **Sahkan dan catat stok**.
   - Buka tugas dari **Perlu tinjauan manual**. Lengkapi tanggal `2026-11-16`, pemasok `PEMASOK DEMO`, jenis tebu `BL`, berat `1250` dan catatan pemeriksaan. Simpan draf dan sahkan ke kloter `OCR-B-UJI`.
   - Buka **Nota Produksi** revisi kedua. Validasi blok `DEMO-A` ke kloter A dengan `90` L dan blok `DEMO-B` ke kloter B dengan `85` L. Isi waktu penggilingan `2026-11-16T09:00:00+07:00` pada kedua blok. Angka liter berasal dari input eksplisit pengujian.

5. Buka **Kloter** dan pilih kloter A. Periksa berat 1250 kg, nira tersedia 90 L, serta referensi dan foto kedua nota sah. Pilih **Tambah batch**, kode `SMOKE-UJI`, wajan 1, waktu masak `2026-11-16T10:00:00+07:00`, 40000 mL nira, hasil fisik 26 kg, grade A 25 kg dan Rp20000/kg. Isi biaya tebu, operasional, bahan dan lainnya masing-masing Rp100000, Rp20000, Rp5000 dan Rp0. Pilih **Reservasi nira**, lalu **Validasi** di Detail Batch.
6. Di **Laporan**, pilih semua tanggal atau 16 November 2026 dan cocokkan angka pada tabel. Dari **Beranda → Rekap**, gunakan **Simpan PDF** dan periksa periode, `SMOKE-UJI` dan 25 kg gula final. Simpan bukti visual Detail Kloter, Laporan, dan Pengaturan pada ukuran 418 × 966. Bandingkan dengan build acuan UI tim pada ukuran yang sama, dengan memperhitungkan data fixture dan aksi yang bergantung pada akun. Simpan PDF serta hasil terminal `Smoke Flutter dan PostgreSQL lulus` dari setiap checkout. Tekan Ctrl+C sebelum menjalankan checkout berikutnya.

   | Pemeriksaan | Hasil yang diharapkan |
   | --- | --- |
   | Adapter WhatsApp simulasi | Foto diterima segera, OCR membaca 1250 kg pada nota truk dan dua blok pada nota produksi. Pengiriman ulang nota truk memakai revisi yang sama. Revisi produksi kedua membaca hasil 26 kg. Konfirmasi revisi lama ditolak. |
   | Pembukuan PostgreSQL | Penerimaan 1250 kg per kloter, penggilingan sebesar −1250 kg per kloter, nira A 90 L dan B 85 L. Satu reservasi dikonsumsi 40 L, tersisa 50 L di A setelah replay pengesahan dan reservasi. |
   | Laporan resmi kloter A | 25 kg gula final, Rp500.000 nilai produksi, Rp125.000 biaya, dan Rp375.000 margin sementara. ID snapshot API rekap dan laba sama dengan PostgreSQL pada putaran itu. ID yang dibuat server dapat berbeda antar-putaran. |
   | Keanggotaan | `admin@example.invalid` mengesahkan. `owner@example.invalid` membaca batch dan laporan dengan penolakan pengesahan batch (`403`). `other@example.invalid` membaca laporan kosong pabriknya sendiri dengan penolakan batch pabrik A (`403`) dan tugas review pabrik A (`404`). Ketiga akun sintetis menggunakan kata sandi `sobatnira-demo`. |
   | WhatsApp perangkat | Catat terpisah mengikuti [uji WhatsApp nyata](#smoke-test-setelah-pairing). Simulasi menguji adapter, balasan dan OCR lokal. Status pengiriman dan waktu tampil pada perangkat memerlukan uji gateway WhatsApp. |

Jika port web diubah melalui `LOCAL_WEB_PORT`, buat ulang build dengan port yang sama pada kedua definisi URL. Di preview lokal, formulir Pengaturan tanpa kontrak API memakai data sesi sintetis. Pengelolaan operator WhatsApp, pemasok, dan jenis tebu memakai API pabrik. Event `whatsapp_photo_accepted`, `ocr_attempt` dan `whatsapp_notice_delivery` dapat dicocokkan lewat `revisionId`. Catat waktu penerimaan, waktu sejak revisi dibuat sampai percobaan OCR (`queueMs`), durasi ekstraksi (`extractionMs`) dan durasi pengiriman per jenis nota. Ukur persentil dan hasil tinjauan manual di staging dengan sampel yang sudah dianonimkan.

### Acceptance otomatis di Chrome

Untuk menggantikan langkah browser manual, gunakan `--acceptance-browser` bersama `--web` setelah membangun Flutter dan menyiapkan database kosong. Chrome harus terpasang. Npm mengambil Playwright CLI 0.1.25 pada putaran pertama dan dapat memakai cache npm untuk putaran selanjutnya. Runner membuka profil terisolasi di ukuran 418 × 966 dan zona waktu Asia/Jakarta setelah tiga tugas OCR siap. Layanan yang dimulai runner ditutup saat selesai.

```powershell
$env:LOCAL_DATABASE_URL = 'postgres://postgres:sobatnira-local@127.0.0.1:55437/sobatnira_accept_a'
$env:LOCAL_ACCEPTANCE_OUTPUT_DIR = 'output/playwright/checkout-a'
npm.cmd run local:stack -- --web --acceptance-browser
```

Jalankan perintah yang sama dari checkout B dengan database dan direktori bukti berbeda. Simpan SHA checkout A/B di catatan pengujian. Gunakan direktori baru setiap kali. Jalankan putaran secara bergiliran setelah build selesai agar kedua pengujian memakai port 8000 dan kompilasi tidak berebut memori dengan OCR. Setelah dua putaran lulus, bandingkan dari `apps/api` memakai path absolut kedua folder.

```powershell
node scripts/compare-acceptance.mjs <direktori-bukti-A> <direktori-bukti-B>
```

Runner menyimpan `acceptance.json`, PDF Rekap Flutter, teks PDF yang dinormalisasi, serta tangkapan layar Detail Kloter, Laporan, Pengaturan dan Ekspor laporan. Di Flutter, owner membuat ekspor, membuka ulang lewat ID yang sama, lalu mengunduh `owner-flutter.pdf` dan `owner-flutter.xlsx`. Fixture juga menguji pertanyaan OpenClaw, ekspor dari WhatsApp, dan receipt notifikasi simulasi. Untuk pertanyaan gabungan produksi dan grade, peringkat ambigu meminta klarifikasi. Dengan basis tanggal penerimaan kloter batch, hasil yang diharapkan adalah 25 kg grade A dan 40.000 mL dari kloter `OCR-A-UJI`. Artefak ekspor WhatsApp disimpan sebagai `owner-rekap.pdf` dan `owner-rekap.xlsx`. Pembanding memeriksa nilai bisnis, pemeriksaan akses, serta isi PDF Flutter. Bandingkan tangkapan layar untuk perbedaan visual karena versi Chrome dan sistem operasi dapat memengaruhi piksel. Jika automasi browser gagal, buka `browser-error.txt` dan snapshot di direktori bukti. Simpan berkas bukti di luar commit.

Untuk membuka kembali database sintetis yang sudah diisi acceptance, gunakan `LOCAL_DATABASE_URL` dari putaran tersebut. Aktifkan endpoint owner dan ekspor secara eksplisit bila diperlukan.

```powershell
$env:OWNER_AGENT_ENABLED = 'true'
$env:REPORT_EXPORT_ENABLED = 'true'
npm.cmd run local:stack -- --web
```

Gunakan `--smoke` untuk menguji foto ambigu dan foto ulang. Mode `--smoke` mencetak kode kloter dan batch yang dibuat untuk putaran tersebut. Tes PostgreSQL komponen juga memeriksa lease kedaluwarsa akibat restart dan kegagalan provider yang menuju antrean **Perlu tinjauan manual**.

Untuk menguji sampai antrean **Pekerjaan** dengan PaddleOCR CPU lokal tanpa membuka Flutter, jalankan `npm run local:stack -- --ocr-smoke` dari `apps/api` memakai database pengembangan sintetis. Perintah memeriksa foto truk, dua revisi produksi, penolakan konfirmasi saat klarifikasi masih terbuka, penolakan format angka ambigu, foto ulang, dan tinjauan manual. Layanan yang dimulai oleh perintah ini ditutup setelah tes selesai.

### Percakapan operator

- Balasan **“Foto diterima. Sedang membaca nota…”** dikirim setelah API menyimpan foto dan pekerjaan OCR. Gunakan **STATUS** untuk cek progres. Jika ada beberapa nota dalam satu chat, balas foto atau ringkasan nota yang dimaksud dengan **STATUS**.
- Balas pesan otomatis yang memuat pertanyaan dengan **JAWAB** diikuti nilai pada nota. Gunakan `1250` untuk berat 1.250 kg dan `12,5` untuk desimal. Bot mengirim ringkasan revisi terbaru setelah koreksi. Balas **KONFIRMASI** hanya ketika data pada ringkasan terbaru sudah sesuai.
- Untuk revisi nota produksi, kirim foto dengan membalas pesan nota yang terverifikasi di percakapan itu. Jika bot meminta pilihan, tandai foto dengan **REVISI <ID>** dari daftar yang tampil, atau **BARU** untuk nota baru.
- `workflow_status` dan `can_confirm` pada status internal menunjukkan tahap dan kesiapan operator. `pending_question` merujuk pada pertanyaan aktif. Tanda terima pengiriman mengikat pertanyaan ke pesan WhatsApp yang menampilkannya. **STATUS** dapat meminta pengiriman ulang jika pengiriman gagal atau ringkasan lama belum menyimpan ikatan pertanyaan.
- Jalankan `npm run db:migrate:ocr` sebelum memperbarui API dan plugin OpenClaw bersama-sama. Migrasi tambahan mempertahankan tanda terima lama. Untuk draf yang dibuat sebelumnya, pertanyaan wajib dilengkapi sewaktu operator memeriksa status.

### Pengukuran

Korelasikan log dengan `revisionId`. Gunakan `whatsapp_photo_reply_dispatch` dengan `queued=true` dan `duplicate=false`. `adapterToDispatchMs` mencakup intake dari awal adapter. `apiResponseToDispatchMs` memakai jam monoton adapter. `commitToDispatchMs` memakai waktu NestJS sesudah konfirmasi commit sampai dispatcher menerima balasan pertama. Gunakan metrik lintas proses ini pada mesin yang sama atau dengan jam tersinkronisasi. Receipt ringkasan hasil di `whatsapp_notice_delivery` hanya menyatakan hasil dari adapter pengirim. Waktu balasan muncul di perangkat perlu diukur pada smoke WhatsApp nyata.

Dalam `ocr_attempt`, kelompokkan percobaan pertama dan retry. `queueMs` dihitung dari pembuatan revisi. `eligibleWaitMs` dihitung dari saat job tersedia kembali atau lease lama kedaluwarsa. `extractionMs` mencatat panggilan NestJS ke FastAPI. `mediaMs`, `inferParseMs`, `rereadAttempts`, dan `rereadMs` memisahkan pengambilan foto, inferensi plus parsing, dan kerja tambahan crop ketika data tersedia. Log agregat memakai ID korelasi serta kode hasil, tanpa nilai nota atau nomor operator.

`requestId` menghubungkan `ocr_attempt` dengan ekstraksi FastAPI pada percobaan tersebut. Bila selective reread dijalankan, `visionModel` dan `visionPromptVersion` mencatat versi yang dipakai. Penggunaan token hanya tersedia di envelope apabila provider mengirim metadata numerik. Benchmark lokal menerima `row_group_sizes` pada nota produksi serta melaporkan `production_row_grouping` dan `field_status_confusion`.

Detail Pekerjaan mengirim `revision_id` saat menandai notifikasi dibaca. Audit `REVIEW_OPENED` menyimpan pembukaan pertama per revisi dan reviewer berwenang. Klien lama masih dapat menandai notifikasi tanpa mencatat pembukaan revisi. Dari terminal privat operator database, jalankan `psql -v factory_id=<UUID> -v from=<ISO-8601> -f scripts/review-timing.sql` dari `apps/api`, memakai koneksi dan `search_path` OCR yang sama dengan NestJS. Query menampilkan agregat dari tugas dibuat ke pembukaan pertama dan dari pembukaan revisi ke keputusan reviewer yang sama. Angka ini adalah waktu berlalu. Laporkan jumlah keputusan yang tidak dapat dipasangkan dengan pembukaan sebagai cakupan yang belum terukur.

#### Dataset dan metrik akurasi

Jalankan regresi sintetis dari `apps/ai` dengan `uv run --locked --extra paddle python benchmark_ocr.py fixtures/acceptance/ground-truth.json --split test`. Pembacaan standar memakai decoder, PaddleOCR, dan parser grid yang sama dengan layanan. Catat SHA, model, perangkat, dan kondisi cache. Untuk nota lapangan, gunakan manifest privat dengan foto anonim yang disetujui, di luar Git. Catat tipe nota, tingkat keterbacaan, kondisi buram, gelap, miring atau terpotong, tulisan tangan, format angka, serta hubungan foto ulang dan revisi. Gunakan `document_group` yang sama untuk semua foto satu nota. Pisahkan grup antara `tuning` dan `test` dan beri `--split` secara eksplisit saat mengukur. Pertahankan set uji dan labelnya setelah penyetelan dimulai.

- Pakai `fields` untuk `raw_value`, `normalized_value`, `unit`, dan status sesuai anotasi yang tersedia. Isi `required_fields` secara eksplisit sesuai tahap nota. Nilai harus cocok dengan seluruh atribut yang dianotasi. Field yang wajib dan terbaca tetapi hilang dihitung sebagai salah. Anotasi `ILLEGIBLE`, `AMBIGUOUS`, dan `NOT_PRESENT` dilaporkan terpisah. Nilai definitif yang dihasilkan pada field tersebut perlu ditinjau. Tampilkan jumlah nota serta field yang dapat dinilai sebagai penyebut.
- Hitung nota dengan semua field wajib benar dari nota yang seluruh field wajibnya dapat dinilai. Untuk pembukuan, bandingkan nilai pada revisi sah, pemetaan kloter, dan catatan batch resmi dengan label privat. Laporkan jumlah nota sah yang memiliki minimal satu kesalahan kritis dibagi jumlah nota sah yang dapat dinilai. Jangan gunakan `wrong_read` pada draf sebagai pengganti metrik pengesahan.
- Hitung nota dengan koreksi dari `OPERATOR_CORRECTED`, `CLARIFICATION_ANSWERED`, atau `ADMIN_CORRECTED`, dan nota difoto ulang dari `PHOTO_RETAKE_QUEUED`, masing-masing dibagi jumlah nota masuk dalam jendela yang sama. Untuk mengurutkan penyebab, tinjau audit bersama label dan hitung satu kali per field logis per nota. Pisahkan salah baca, salah parsing, salah normalisasi, salah pemetaan, dan nilai yang baru tersedia pada revisi lanjutan.
- Gunakan median dan rentang untuk sampel kecil. Benchmark menahan p95 sampai tersedia 100 grup nota independen untuk agregat yang dilaporkan. Jalankan perbandingan pembacaan standar, crop, dan fallback pada set uji yang sama setelah data dan penggunaan provider disetujui. Laporkan perbaikan field kritis, proporsi nota yang memicu panggilan tambahan, delta waktu, dan biaya sesuai catatan pemakaian provider. Ambang dan target operasional mengikuti hasil pilot.

## Mode terhubung

Jalankan gateway, NestJS dan FastAPI pada host yang sama untuk memakai alamat loopback di contoh. Gunakan HTTPS dan origin Flutter yang eksplisit bila diakses lewat jaringan. Untuk OpenClaw 2026.11.4 gunakan Node 24.16+ pada seri 24 atau Node 26.1+.

1. Buat `.env.connected` dari [contoh konfigurasi](../../.env.connected.example) jika file privat tersebut belum ada. Lengkapi nilai berikut pada host yang menjalankan layanan.

   | Komponen | Nilai yang dibutuhkan |
   | --- | --- |
   | PostgreSQL | `DATABASE_URL` dari session pooler atau koneksi langsung. Isi `DATABASE_SSL_CA_FILE` dengan path CA proyek Supabase dari dashboard. Koneksi jarak jauh memverifikasi TLS. |
   | Supabase Auth | `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`. Buat akun administrator dengan metode email/password dan salin UUID akun. |
   | Penutupan kloter | Biarkan `BATCH_API_BASE_URL` kosong agar NestJS membaca status batch resmi dari PostgreSQL yang sama. [Pemeriksaan penutupan](../backend-production-implementation.md#penutupan-kloter). |
   | R2 | `R2_ENDPOINT` berupa endpoint S3 akun, `R2_BUCKET_NAME`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`. Nonaktifkan akses melalui `r2.dev` dan custom domain publik di dashboard bucket. Jika terdapat hostname publik lama, isi `R2_PUBLIC_BASE_URL` untuk probe dengan satu marker sintetis. Probe membutuhkan izin PutObject dan DeleteObject. |
   | Gemini | `GEMINI_API_KEY`, `GEMINI_VISION_MODEL` berisi ID model Gemini yang dapat memproses gambar dan mengembalikan JSON. |
   | OpenRouter | `OPENROUTER_API_KEY`, `OPENROUTER_AGENT_MODEL`, `OPENROUTER_ALLOWED_PROVIDERS` berupa slug yang disetujui dan dipisah koma. Pilih endpoint zero data retention yang mendukung function calling. ID model eksplisit boleh memakai akhiran `:free`. `OPENROUTER_AGENT_FALLBACK_MODEL` opsional. Set `OPENROUTER_AGENT_DISABLE_REASONING=true` bila model yang dipilih mendukung `reasoning.effort=none`. |
   | Token internal | Isi `AI_SERVICE_INTERNAL_TOKEN` dan `WHATSAPP_ADAPTER_INTERNAL_TOKEN` dengan dua nilai acak terpisah minimal 32 karakter. Untuk setiap nilai jalankan `node -p "require('node:crypto').randomBytes(32).toString('hex')"` di terminal privat. |
   | WhatsApp | `SOBATNIRA_API_URL` dan `SOBATNIRA_WHATSAPP_ACCOUNT_ID` harus cocok dengan alamat API internal dan akun gateway. |
   | Scope pabrik | `SETUP_FACTORY_ID`, `SETUP_OPERATOR_PHONE` dalam E.164, `SETUP_OPERATOR_NAME`, `SETUP_ADMIN_USER_ID`, dan bila diperlukan `SETUP_OWNER_USER_ID`. Gunakan ID pabrik yang disepakati tim. |

   Workflow memakai PostgreSQL untuk antrean. Flutter cukup menerima URL Supabase, publishable key, dan alamat API sebagai `--dart-define`. Panduan TLS dan konfigurasi provider tersedia di [Supabase](https://supabase.com/docs/guides/platform/ssl-enforcement), [Gemini](https://ai.google.dev/gemini-api/docs/image-understanding), dan [OpenRouter](https://openrouter.ai/docs/features/tool-calling).

   Konfigurasi smoke yang sudah diuji memakai `GEMINI_VISION_MODEL=gemini-3.1-flash-lite`, `OPENROUTER_AGENT_MODEL=inclusionai/ling-3.2-flash:free`, `OPENROUTER_ALLOWED_PROVIDERS=antdigital/fp8`, dan `OPENROUTER_AGENT_DISABLE_REASONING=true`. Ulangi smoke saat mengganti model atau provider.

2. Dari `apps/api`, periksa infrastruktur, terapkan migration produksi dan OCR pada database yang sama, lalu daftarkan akun berpabrik. Migration membutuhkan principal backend yang berhak membuat tabel workflow dan memakai RLS. Provisioning dapat diulang dan menolak konflik antara keanggotaan yang sudah ada dan isian baru. Rincian migration produksi ada di [panduan backend](../backend-configuration.md).

   ```sh
   node --env-file=../../.env.connected dist/documents/setup.js check --infra-only
   node --env-file=../../.env.connected dist/database/migrate.js
   node --env-file=../../.env.connected dist/documents/migrate.js
   node --env-file=../../.env.connected dist/documents/setup.js provision
   ```

   Buat akun dan berikan membership tenant serta pabrik di modul produksi sebelum `provision`. Gunakan role `admin` untuk `SETUP_ADMIN_USER_ID` dan `owner` untuk `SETUP_OWNER_USER_ID` jika diisi. Pengesahan kedua jenis nota memakai ID pabrik yang sama dengan `SETUP_FACTORY_ID`. Siapkan pemasok aktif dan dua kloter uji yang belum dibukukan pada pabrik pengembangan untuk smoke test. [Panduan otorisasi](../backend-authentication.md), [penerimaan dari nota OCR](../backend-intake-documents.md#penerimaan-dari-nota-ocr).

3. Jalankan NestJS dari `apps/api` dengan `node --env-file=../../.env.connected dist/main.js`. Jalankan FastAPI dari `apps/ai` dengan perintah berikut. Jika port diubah, samakan `OCR_MEDIA_BASE_URL` dan `AI_BASE_URL` dengan alamat masing-masing layanan.

   ```sh
   uv run --locked --extra paddle --env-file ../../.env.connected uvicorn main:app --host 127.0.0.1 --port 8000
   ```

4. Dari root repositori, instal plugin WhatsApp dan tautkan plugin intake.

   ```sh
   npm install -g openclaw@2026.11.4
   openclaw plugins install npm:@openclaw/whatsapp@2026.11.4
   openclaw plugins install --link --no-enable ./apps/api/integrations/openclaw
   ```

   Terapkan bagian relevan dari [contoh konfigurasi OpenClaw](openclaw.example.json) ke `<state-dir>/openclaw.json`. State directory bawaan berada di `~/.openclaw`. Ganti nomor contoh dengan nomor operator terdaftar, isi `mediaDir` dengan path absolut `<state-dir>/media`, dan pertahankan entri lain yang dipakai gateway di `plugins.allow`. Gunakan `openclaw channels login --channel whatsapp --account sobatnira` dan pindai QR dari **Perangkat tertaut** pada nomor WhatsApp SobatNira.

   Berikan `SOBATNIRA_MODE`, `SOBATNIRA_API_URL`, `SOBATNIRA_WHATSAPP_ACCOUNT_ID`, `WHATSAPP_ADAPTER_INTERNAL_TOKEN`, serta pengaturan `OPENROUTER_*` dari langkah 1 melalui lingkungan proses gateway atau file privat `<state-dir>/.env`. Jika gateway memakai autentikasi token, isi `OPENCLAW_GATEWAY_TOKEN` dengan nilai acak terpisah. Jalankan `openclaw config validate` untuk memeriksa contoh konfigurasi. Pada `openclaw plugins inspect sobatnira-intake --runtime`, pastikan status `loaded` dengan hook `reply_dispatch` dan layanan `sobatnira-notices`. Jalankan `openclaw gateway` dan periksa `openclaw channels status --probe`. Akun `sobatnira` harus terhubung dan plugin harus aktif. [Pairing WhatsApp](https://docs.openclaw.ai/channels/whatsapp), [hook pesan](https://docs.openclaw.ai/plugins/hooks/messages), [lingkungan gateway](https://docs.openclaw.ai/help/environment).

   Bila Windows sudah memiliki layanan OpenClaw, siapkan instance SobatNira dengan profil, file konfigurasi, direktori state, workspace, dan port tersendiri. Jalankan pemasangan plugin dan validasi dengan profil yang sama. Set `gateway.port` pada konfigurasi profil agar perintah pairing dan status menargetkan gateway SobatNira. Tunggu gateway siap di terminal pertama, lalu jalankan pairing di terminal kedua dengan lingkungan profil yang sama.

   ```powershell
   # Terminal gateway
   openclaw --profile sobatnira-demo gateway --port 19089
   # Terminal pairing
   openclaw --profile sobatnira-demo channels login --channel whatsapp --account sobatnira --verbose
   openclaw --profile sobatnira-demo channels status --probe
   ```

   Jika CLI melaporkan direktori state yang berbeda, periksa profil, port, `OPENCLAW_STATE_DIR`, dan `OPENCLAW_CONFIG_PATH` pada kedua terminal. Mode `--verbose` menampilkan alasan kegagalan login. [Beberapa gateway pada satu host](https://docs.openclaw.ai/gateway/multiple-gateways).
5. Dari `apps/api`, jalankan `node --env-file=../../.env.connected dist/documents/setup.js check`. Perintah memeriksa migration OCR dan produksi, token internal, worker, mode NestJS dan FastAPI, operator aktif dan kedua lapisan membership reviewer untuk pabrik yang sama, PostgreSQL, Supabase Auth, R2, PaddleOCR serta akses API/model Gemini dan OpenRouter. Kesalahan menampilkan komponen dan nama variabel untuk diperiksa. Untuk pemeriksaan terpisah gunakan `check-scope` atau `check-media-privacy`.

   Dari `apps/mobile`, buat build web dengan mode terhubung dan konfigurasi publik proyek. Ganti ketiga nilai contoh berikut sebelum build.

   ```sh
   flutter build web --dart-define=SOBATNIRA_MODE=connected --dart-define=API_BASE_URL=https://api.example.invalid --dart-define=SUPABASE_URL=https://project.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_EXAMPLE
   ```

   Sajikan `build/web` dari origin yang terdaftar di `CORS_ORIGINS`. Masuk dengan akun Supabase. Beranda membuka pabrik pertama yang dapat diakses. Jika akun mempunyai akses ke beberapa pabrik, gunakan pemilih di profil Beranda. Buka **Pekerjaan** untuk meninjau nota, **Kloter** untuk detail dan saldo nira, atau **Laporan** dan aksi **Rekap** untuk melihat data yang sudah disahkan.

   Jika probe privasi R2 gagal karena koneksi ke hostname lama terputus, cocokkan hostname dengan daftar domain publik bucket di dashboard R2 dan ulangi `check-media-privacy` dari host deployment. Bila hostname lama sudah dihapus dan dashboard menunjukkan seluruh akses publik dinonaktifkan, `R2_PUBLIC_BASE_URL` boleh dikosongkan. Verifikasi ini terpisah dari pemeriksaan akses S3.

### Smoke test setelah pairing

1. Dari `apps/ai`, jalankan `uv run --locked --extra paddle python synthetic_notes.py ../../.tmp/live-fixtures`. Kirim `truck.png` dari nomor operator terdaftar. Periksa tanda terima, ringkasan otomatis, dan berat 1250 kg. Ketik `STATUS` di chat yang sama untuk melihat nota terakhir. Balas ringkasan otomatis dengan `KONFIRMASI`. Di Pekerjaan buka badge laporan baru, periksa foto dan evidence, lalu sahkan ke kloter uji A. Status harus `VALIDATED` setelah halaman dimuat ulang.
2. Kirim `manual.png` dan buka tugasnya dari **Perlu tinjauan manual**. Isi tanggal `2026-11-16`, pemasok `PEMASOK DEMO`, jenis tebu `BL`, berat `1250` dan catatan pemeriksaan. Simpan draf, lalu sahkan ke kloter uji B. Periksa kredit 1250 kg pada masing-masing kloter.
3. Kirim `production.png` dengan caption `BARU`. Balas pesan ringkasannya dengan `update.png`. Pastikan ID dokumen sama, revisi bertambah, dan hasil baris pertama menjadi 26 kg. Balas ke foto terkini dengan pertanyaan pendek untuk menjalankan OpenRouter. Cocokkan tool call dengan aktivitas di dashboard provider karena template dapat dipakai bila provider gagal. Konfirmasi revisi terbaru, lalu validasi kedua blok dengan memilih kloter uji dan memasukkan liter serta waktu penggilingan seperti smoke lokal. Periksa debit tebu dan kredit nira.
4. Kirim `ambiguous.png` untuk memicu Gemini dengan crop angka berat. Pastikan aktivitas generate muncul dan hasil atau kegagalannya tercatat pada envelope OCR. Balas ringkasan otomatis dengan `JAWAB 1250`. Ulangi pada kutipan lama dan pastikan perintah ditolak. Kirim `unreadable.png`, lalu balas ringkasannya dengan foto baru dan caption `FOTO ULANG`. Foto ulang harus menyimpan revisi baru dengan riwayat asli.

Gateway hanya menangani DM pada akun yang dikonfigurasi. NestJS mengotorisasi setiap perubahan dan membatasi rujukan kutipan ke percakapan serta pabrik yang sama. Pakai `REVISI <dokumen>` jika kutipan belum bisa dipetakan. Foto dengan byte yang sama pada operator dan chat yang sama memakai kembali pengiriman terdahulu. `BARU` menyatakan nota baru, dan `FOTO ULANG` menyatakan penggantian revisi secara eksplisit. Pesan ringkasan dapat terkirim ulang jika gateway berhenti setelah WhatsApp menerima pesan dan sebelum PostgreSQL mencatat receipt. Penerimaan foto, revisi dan konfirmasi tetap memakai idempotensi backend.

Ketik `BANTUAN` untuk petunjuk atau `STATUS 2` untuk halaman berikutnya di nota produksi. Untuk membaca ulang foto asli setelah layanan OCR gagal, balas ringkasan otomatisnya dengan `COBA LAGI`. Backend membuat revisi pembacaan baru dari foto yang sama serta mempertahankan riwayat. Perintah yang mengubah dokumen terikat ke ringkasan revisi aktif yang dikutip. Sintaks ber-ID tetap bisa dipakai untuk pelacakan teknis.

## Pengelolaan operator WhatsApp

Di Flutter mode terhubung, masuk sebagai admin atau owner, pilih pabrik di **Kloter**, lalu buka **Operator WhatsApp**. Daftar mendukung pencarian nama dan nomor serta filter status. Gunakan **Tambah operator WhatsApp** untuk mendaftarkan nomor, ikon edit untuk mengubah nama dan status, atau ikon riwayat untuk melihat perubahan.

Admin dan owner dengan membership aktif dapat mengelola operator pada pabrik yang dipilih. Kirim token akses Supabase sebagai `Authorization: Bearer <access_token>`. Route dasar memakai `/tenants/:tenantId/factories/:factoryId/operators`.

| Metode dan path relatif | Fungsi |
| --- | --- |
| `GET /` | Daftar operator dengan pencarian nama atau nomor (`q`), filter `isActive`, serta `limit` dan `offset`. |
| `POST /` | Daftarkan operator aktif dengan `displayName` dan `phoneE164` dalam format E.164. Nomor yang sudah terdaftar menghasilkan `409 Conflict`. |
| `PATCH /:operatorId` | Ubah `displayName` atau `isActive`. Kirim `isActive: false` untuk menonaktifkan dan `isActive: true` untuk mengaktifkan kembali. |
| `GET /:operatorId/history` | Baca riwayat pembuatan dan perubahan, termasuk akun yang bertindak, waktu, serta nama dan status sebelum dan sesudah. Mendukung `limit` dan `offset`. |

Nomor terikat pada satu pabrik. Untuk mengganti nomor operator, tambahkan kontak dengan nomor baru lalu nonaktifkan kontak lama. Setelah dinonaktifkan, pengiriman nota baru dari nomor tersebut ditolak. Foto, dokumen, dan riwayat yang sudah tersimpan tetap tersedia melalui alur yang berwenang.

Sebelum menggunakan API ini, terapkan migration OCR `006_operator_management_audit.sql` dengan `npm run db:migrate:ocr` dari `apps/api` dengan konfigurasi database tujuan. Untuk mode terhubung, perbarui juga allowlist OpenClaw agar nomor aktif baru dapat mengirim pesan ke gateway.

## Tes komponen

- `apps/api`: siapkan PostgreSQL pengujian dengan role `anon`, `authenticated` dan tabel `auth.users` sintetis sesuai langkah CI. Jalankan `npm run db:migrate` dengan `DATABASE_URL` pengujian, lalu `npm test` dengan `TEST_DATABASE_URL` menunjuk database yang sama. Tes menyiapkan dan membersihkan schema OCR sendiri.
- `apps/ai`: jalankan `uv run --locked python -m unittest`. Untuk benchmark PaddleOCR CPU gunakan `uv run --locked --extra paddle python benchmark_ocr.py <manifest.json>`. Isi manifest berupa array objek dengan key `image`, `document_type`, dan `fields` yang dipetakan dari path field ke nilai seperti `{"normalized_value": 1250, "unit": "kg"}`.
- `apps/mobile`: jalankan `flutter analyze` dan `flutter test`.
