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
3. Dari `apps/mobile` jalankan Flutter web dan buka `http://127.0.0.1:8080`. Untuk melihat aplikasi release, gunakan `flutter build web` dengan ketiga `--dart-define` yang sama, lalu sajikan `build/web` pada port 8080.

   ```sh
   flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080 --dart-define=API_BASE_URL=http://127.0.0.1:3000 --dart-define=SUPABASE_URL=http://127.0.0.1:8077 --dart-define=SUPABASE_PUBLISHABLE_KEY=local-synthetic-publishable
   ```

4. Pada layar awal pilih **Masuk** dan isi `admin-demo` / `sandi-demo`. Buka **Pekerjaan** dan masuk dengan `admin@example.invalid` / `sobatnira-demo`. Setelah terminal menampilkan ID tugas, muat ulang daftar, buka **Nota Kedatangan Truk** dari Operator Demo, periksa foto, evidence, dan riwayat, lalu pilih **Validasi revisi ini**. Terminal menyatakan lulus setelah membaca status `VALIDATED` langsung di PostgreSQL. Biarkan proses berjalan untuk melihat hasil dan gunakan Ctrl+C untuk menghentikannya.

Uji memeriksa dua tipe nota, kutipan pesan bot pada foto produksi lanjutan, kiriman duplikat, operator nonaktif, revisi lama, akses lintas pabrik dan foto ulang. Tes PostgreSQL komponen juga memeriksa lease kedaluwarsa akibat restart dan kegagalan kontrak provider yang menuju antrean **Tinjauan manual**. Untuk menjalankan layanan tanpa memasukkan kiriman uji, hilangkan `--smoke`. Jalankan smoke lagi untuk menambah kiriman baru. Gunakan tugas baru dengan status menunggu validasi pada percobaan ini.

## Mode terhubung

Jalankan gateway, NestJS dan FastAPI pada host yang sama untuk memakai alamat loopback di contoh. Gunakan HTTPS dan origin Flutter yang eksplisit bila diakses lewat jaringan. Untuk OpenClaw 2026.11.4 gunakan Node 24.16+ pada seri 24 atau Node 26.1+.

1. Buat `.env.connected` dari [contoh konfigurasi](../../.env.connected.example) jika file privat tersebut belum ada. Lengkapi nilai berikut pada host yang menjalankan layanan.

   | Komponen | Nilai yang dibutuhkan |
   | --- | --- |
   | PostgreSQL | `DATABASE_URL` dari session pooler atau koneksi langsung. Isi `DATABASE_SSL_CA_FILE` dengan path CA proyek Supabase dari dashboard. Koneksi jarak jauh memverifikasi TLS. |
   | Supabase Auth | `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`. Buat akun administrator dengan metode email/password dan salin UUID akun. |
   | R2 | `R2_ENDPOINT` berupa endpoint S3 akun, `R2_BUCKET_NAME`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`. Nonaktifkan akses melalui `r2.dev` dan custom domain publik di dashboard bucket. Jika terdapat hostname publik lama, isi `R2_PUBLIC_BASE_URL` untuk probe dengan satu marker sintetis. Probe membutuhkan izin PutObject dan DeleteObject. |
   | Gemini | `GEMINI_API_KEY`, `GEMINI_VISION_MODEL` berisi ID model Gemini yang dapat memproses gambar dan mengembalikan JSON. |
   | OpenRouter | `OPENROUTER_API_KEY`, `OPENROUTER_AGENT_MODEL`, `OPENROUTER_ALLOWED_PROVIDERS` berupa slug yang disetujui dan dipisah koma. Pilih endpoint zero data retention yang mendukung function calling. `OPENROUTER_AGENT_FALLBACK_MODEL` opsional. |
   | Token internal | Isi `AI_SERVICE_INTERNAL_TOKEN` dan `WHATSAPP_ADAPTER_INTERNAL_TOKEN` dengan dua nilai acak terpisah minimal 32 karakter. Untuk setiap nilai jalankan `node -p "require('node:crypto').randomBytes(32).toString('hex')"` di terminal privat. |
   | WhatsApp | `SOBATNIRA_API_URL` dan `SOBATNIRA_WHATSAPP_ACCOUNT_ID` harus cocok dengan alamat API internal dan akun gateway. |
   | Scope pabrik | `SETUP_FACTORY_ID`, `SETUP_OPERATOR_PHONE` dalam E.164, `SETUP_OPERATOR_NAME`, `SETUP_ADMIN_USER_ID`, dan bila diperlukan `SETUP_OWNER_USER_ID`. Gunakan ID pabrik yang disepakati tim. |

   Workflow memakai PostgreSQL untuk antrean. Flutter cukup menerima URL Supabase, publishable key, dan alamat API sebagai `--dart-define`. Panduan TLS dan konfigurasi provider tersedia di [Supabase](https://supabase.com/docs/guides/platform/ssl-enforcement), [Gemini](https://ai.google.dev/gemini-api/docs/image-understanding), dan [OpenRouter](https://openrouter.ai/docs/features/tool-calling).

2. Dari `apps/api`, periksa infrastruktur, terapkan migration OCR pada database yang dipilih, dan daftarkan akun berpabrik. Migration membutuhkan principal backend yang berhak membuat tabel workflow dan memakai RLS. Provisioning dapat diulang dan menolak konflik antara keanggotaan yang sudah ada dan isian baru. Modul produksi memiliki migration terpisah dalam [panduan backend](../backend-configuration.md).

   ```sh
   node --env-file=../../.env.connected dist/documents/setup.js check --infra-only
   node --env-file=../../.env.connected dist/documents/migrate.js
   node --env-file=../../.env.connected dist/documents/setup.js provision
   ```

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

   Berikan `SOBATNIRA_MODE`, `SOBATNIRA_API_URL`, `SOBATNIRA_WHATSAPP_ACCOUNT_ID`, `WHATSAPP_ADAPTER_INTERNAL_TOKEN`, serta keempat variabel `OPENROUTER_*` melalui lingkungan proses gateway atau file privat `<state-dir>/.env`. Jika gateway memakai autentikasi token, isi `OPENCLAW_GATEWAY_TOKEN` dengan nilai acak terpisah. Jalankan `openclaw gateway`, lalu periksa `openclaw plugins inspect sobatnira-intake --runtime` dan `openclaw channels status --probe`. Akun `sobatnira` harus terhubung dan plugin harus aktif. [Pairing WhatsApp](https://docs.openclaw.ai/channels/whatsapp), [hook pesan](https://docs.openclaw.ai/plugins/hooks/messages), [lingkungan gateway](https://docs.openclaw.ai/help/environment).
5. Dari `apps/api`, jalankan `node --env-file=../../.env.connected dist/documents/setup.js check`. Perintah memeriksa migration, PostgreSQL, Supabase Auth, R2, PaddleOCR serta akses API/model Gemini dan OpenRouter. Kesalahan menampilkan komponen dan nama variabel untuk diperiksa. Gunakan subperintah `check-media-privacy` untuk mengulang pemeriksaan privasi R2 saja. Jalankan Flutter dengan tiga `--dart-define` yang sama seperti mode lokal, menggunakan URL API, URL Supabase, dan publishable key proyek yang sesuai. Login Pekerjaan memakai akun Supabase.

### Smoke test setelah pairing

1. Buat foto dari fixture, dari `apps/ai` jalankan `uv run --locked --extra paddle python synthetic_notes.py ../../.tmp/live-fixtures`. Kirim `truck.png` dari nomor operator yang terdaftar. Periksa tanda terima, pesan ringkasan otomatis, nilai berat 1250 kg, serta perintah `STATUS`. Dari WhatsApp kirim `KONFIRMASI <dokumen> <revisi>`. Di Pekerjaan buka badge laporan baru, periksa foto dan evidence, lalu validasi. Status harus `VALIDATED` setelah halaman dimuat ulang.
2. Kirim `production.png` dengan caption `BARU`. Balas pesan ringkasannya dengan `update.png`. Pastikan ID dokumen sama, revisi bertambah, dan hasil baris pertama menjadi 26 kg. Balas ke foto terkini dengan pertanyaan pendek untuk menjalankan OpenRouter. Cocokkan permintaan berhasil dan tool call dengan aktivitas di dashboard provider karena template dapat dipakai bila provider gagal.
3. Kirim `ambiguous.png` untuk memicu Gemini dengan crop angka berat. Pastikan aktivitas generate Gemini muncul dan hasil pembacaan atau kegagalannya tercatat pada envelope percobaan OCR. Gunakan `JAWAB <dokumen> <revisi> <pertanyaan> <nilai JSON>` untuk memilih nilai dalam simulasi. Coba sekali lagi dengan ID lama untuk memastikan jawaban ditolak.
4. Kirim `unreadable.png`. Periksa bahwa admin dapat membuka **Perlu tinjauan manual** dan operator memperoleh instruksi `FOTO ULANG <dokumen> <revisi>`. Foto ulang menyimpan revisi baru dengan riwayat asli. Untuk menguji pengisian manual, kirim `manual.png`, buka dari antrean pengecualian, lalu isi tanggal `2026-11-16`, pemasok `PEMASOK DEMO`, jenis tebu `BL`, berat `1250`, dan catatan pemeriksaan. Simpan draf, lalu validasi pada tindakan terpisah.

Gateway hanya menangani DM pada akun yang dikonfigurasi. NestJS mengotorisasi setiap perubahan dan membatasi rujukan kutipan ke percakapan serta pabrik yang sama. Pakai `REVISI <dokumen>` jika kutipan belum bisa dipetakan. `BARU` menyatakan nota baru. Pesan ringkasan dapat terkirim ulang jika gateway berhenti setelah WhatsApp menerima pesan dan sebelum PostgreSQL mencatat receipt. Penerimaan foto, revisi dan konfirmasi tetap memakai idempotensi backend.

## Tes komponen

- `apps/api`: jalankan `npm test` dengan `TEST_DATABASE_URL` menunjuk PostgreSQL pengujian. Tes membuat dan menghapus schema sendiri.
- `apps/ai`: jalankan `uv run --locked python -m unittest`. Untuk benchmark PaddleOCR CPU gunakan `uv run --locked --extra paddle python benchmark_ocr.py <manifest.json>`. Isi manifest berupa array objek dengan key `image`, `document_type`, dan `fields` yang dipetakan dari path field ke nilai seperti `{"normalized_value": 1250, "unit": "kg"}`.
- `apps/mobile`: jalankan `flutter analyze` dan `flutter test`.
