# Menjalankan intake dan review nota

Skema JSON dan contoh sintetis tersedia di [schemas](schemas/) dan [examples](examples/). Status pengujian tercatat di [log implementasi](IMPLEMENTATION_LOG.md). PRD dan register keputusan tim disimpan secara privat di `docs/internal/ai/`.

## Instalasi bersama

Siapkan Node 24, uv, Flutter 3.44.6, dan Chrome. Gunakan Python 3.13 pada Windows/Linux x64 untuk PaddleOCR CPU. Dari root repositori, jalankan perintah per direktori.

| Direktori | Perintah |
| --- | --- |
| `apps/api` | `npm ci` dan `npm run build` |
| `apps/ai` | `uv sync --locked --extra paddle --python 3.13` |
| `apps/mobile` | `flutter pub get --enforce-lockfile` |

Panggilan pertama PaddleOCR mengunduh model. Gunakan `PADDLE_PDX_CACHE_HOME` untuk memilih direktori cache. Di PowerShell gunakan `npm.cmd` jika eksekusi `npm.ps1` diblokir.

## Mode lokal sintetis

1. Siapkan PostgreSQL lokal. Jika memakai Docker, jalankan perintah berikut sekali. Pada sesi berikutnya gunakan `docker start sobatnira-local-db` bila berhenti. Untuk PostgreSQL yang sudah tersedia, set `LOCAL_DATABASE_URL` ke koneksi loopback milik pengembangan.

   ```sh
   docker run --name sobatnira-local-db -e POSTGRES_PASSWORD=sobatnira-local -p 127.0.0.1:55437:5432 -d postgres:17
   ```

2. Jalankan `npm run local:stack -- --smoke` dari `apps/api`. Bootstrap membuat schema `sobatnira_local`, menjalankan migration berulang dengan aman, memasang operator/admin sintetis, membuat fixture foto ke `.tmp/local-ai`, dan menyalakan NestJS, worker, FastAPI dan stub Supabase Auth. Media asli sintetis tersimpan privat di `.tmp/local-ai/media`. Plugin OpenClaw yang sama menerima payload sintetis dan mengirim lewat batas WhatsApp simulasi. PaddleOCR menjalankan model CPU dengan foto hasil generasi fixture.
3. Dari `apps/mobile` jalankan Flutter web dan buka `http://127.0.0.1:8080`. Untuk melihat aplikasi release, gunakan `flutter build web` dengan definisi lingkungan yang sama, lalu sajikan `build/web` pada port 8080.

   ```sh
   flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080 --dart-define=SOBATNIRA_MODE=local --dart-define=API_BASE_URL=http://127.0.0.1:3000 --dart-define=SUPABASE_URL=http://127.0.0.1:8077 --dart-define=SUPABASE_PUBLISHABLE_KEY=local-synthetic-publishable
   ```

4. Masuk dengan `admin@example.invalid` / `sobatnira-demo`, buka **Pekerjaan** dari Beranda **Pabrik Demo**. Gunakan ID tugas dan kode kloter yang dicetak terminal.

   - Buka **Nota Kedatangan Truk**, periksa foto dan riwayat, pilih **Validasi revisi ini**, pilih kloter `OCR-A-…`, lalu pilih **Sahkan dan catat stok**.
   - Buka tugas dari **Perlu tinjauan manual**. Lengkapi tanggal `2026-11-16`, pemasok `PEMASOK DEMO`, jenis tebu `BL`, berat `1250` dan catatan pemeriksaan. Simpan draf dan sahkan ke kloter `OCR-B-…`.
   - Buka **Nota Produksi** revisi kedua. Validasi blok `DEMO-A` ke kloter A dengan `90` L dan blok `DEMO-B` ke kloter B dengan `85` L. Isi waktu penggilingan `2026-11-16T09:00:00+07:00` pada kedua blok. Angka liter berasal dari input eksplisit pengujian.

5. Buka **Kloter** dan pilih kloter A. Periksa berat 1250000 g, nira tersedia 90000 mL, serta ID nota truk, nota produksi dan kedua revisinya. Pilih **Tambah batch**. Pakai kode yang dicetak terminal, wajan 1, waktu masak setelah penggilingan, 40000 mL nira, hasil fisik 26 kg, grade A 25 kg dan Rp20000/kg. Isi biaya tebu, operasional, bahan dan lainnya masing-masing Rp100000, Rp20000, Rp5000 dan Rp0. Pilih **Reservasi nira**, lalu **Validasi** di Detail Batch.
6. Buka rekap di **Laporan** dan pilih 16 November 2026 atau semua tanggal. Untuk kloter A, cocokkan 25 kg gula final dan margin Rp375.000 yang masih sementara. Gunakan **Simpan PDF** untuk memeriksa periode dan rincian batch. Terminal memeriksa 50000 mL sisa nira, satu reservasi yang dikonsumsi, replay pengesahan, penolakan akses pabrik lain, dan kesamaan ID snapshot rekap dan laba. Gunakan database lokal khusus demo. Tekan Ctrl+C untuk menghentikan layanan setelah pemeriksaan.

Jika port 8080 sedang dipakai, set `LOCAL_WEB_PORT` ke port alternatif sebelum memulai stack dan gunakan port yang sama untuk Flutter. Event `whatsapp_photo_accepted`, `ocr_attempt` dan `whatsapp_notice_delivery` dapat dicocokkan lewat `revisionId`. Catat waktu penerimaan, waktu sejak revisi dibuat sampai percobaan OCR (`queueMs`), durasi ekstraksi (`extractionMs`) dan durasi pengiriman per jenis nota. Ukur persentil dan hasil tinjauan manual di staging dengan sampel yang sudah dianonimkan.

Uji memeriksa dua tipe nota, kutipan pesan bot pada foto produksi lanjutan, kiriman duplikat, operator nonaktif, revisi lama, akses lintas pabrik dan foto ulang. Tes PostgreSQL komponen juga memeriksa lease kedaluwarsa akibat restart dan kegagalan provider yang menuju antrean **Perlu tinjauan manual**. Untuk menjalankan layanan tanpa memasukkan kiriman uji, hilangkan `--smoke`. Gunakan tugas baru dengan status menunggu validasi pada setiap percobaan.

Untuk menguji sampai antrean **Pekerjaan** dengan PaddleOCR CPU lokal tanpa membuka Flutter, jalankan `npm run local:stack -- --ocr-smoke` dari `apps/api` memakai database pengembangan sintetis. Perintah memeriksa foto truk, dua revisi produksi, penolakan konfirmasi saat klarifikasi masih terbuka, penolakan format angka ambigu, foto ulang, dan tinjauan manual. Layanan yang dimulai oleh perintah ini ditutup setelah tes selesai.

### Percakapan operator

- Balasan **“Foto diterima. Sedang membaca nota…”** dikirim setelah API menyimpan foto dan pekerjaan OCR. Gunakan **STATUS** untuk cek progres. Jika ada beberapa nota dalam satu chat, balas foto atau ringkasan nota yang dimaksud dengan **STATUS**.
- Balas pesan otomatis yang memuat pertanyaan dengan **JAWAB** diikuti nilai pada nota. Gunakan `1250` untuk berat 1.250 kg dan `12,5` untuk desimal. Bot mengirim ringkasan revisi terbaru setelah koreksi. Balas **KONFIRMASI** hanya ketika data pada ringkasan terbaru sudah sesuai.
- `workflow_status` dan `can_confirm` pada status internal menunjukkan tahap dan kesiapan operator. `pending_question` merujuk pada pertanyaan aktif. Tanda terima pengiriman mengikat pertanyaan ke pesan WhatsApp yang menampilkannya. **STATUS** dapat meminta pengiriman ulang jika pengiriman gagal atau ringkasan lama belum menyimpan ikatan pertanyaan.
- Jalankan `npm run db:migrate:ocr` sebelum memperbarui API dan plugin OpenClaw bersama-sama. Migrasi tambahan mempertahankan tanda terima lama. Untuk draf yang dibuat sebelumnya, pertanyaan wajib dilengkapi sewaktu operator memeriksa status.

### Pengukuran

Ambil median dan p95 per tipe nota. `whatsapp_photo_reply_dispatch` mengukur waktu dari event masuk hingga balasan masuk antrean pengiriman gateway. Bandingkan dengan waktu balasan terlihat pada perangkat operator saat smoke WhatsApp live. Untuk hasil awal setiap foto, `whatsapp_notice_delivery` dengan hasil `SENT` mencatat `photoRecordedToProviderAckMs` dari pencatatan foto sampai tanda terima provider. Gunakan `ocr_attempt` untuk memisahkan waktu antrean dan inferensi. Koreksi operator serta foto ulang dapat dihitung dari `OPERATOR_CORRECTED`, `CLARIFICATION_ANSWERED`, dan `PHOTO_RETAKE_QUEUED` pada audit.

Dari `apps/ai`, jalankan `uv run --locked --extra paddle python benchmark_ocr.py <manifest-privat.json>` terhadap sampel anonim berlabel. Statistik agregat membedakan kolom yang kosong, salah baca, serta nilai salah yang diterima sebagai `READ`. Bagian kalibrasi membandingkan bacaan yang akan lolos pada beberapa ambang untuk berat bersih dan berat hasil. Hasil ini belum menerapkan ambang baru pada OCR. Gunakan baseline nota lapangan sebelum menetapkan ambang atau target waktu.

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
