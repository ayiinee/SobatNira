# Konfigurasi backend dan pemeriksaan koneksi

Panduan ini melengkapi [setup development](development.md) untuk koneksi Supabase Auth, PostgreSQL, Cloudflare R2, Redis/Upstash dan FastAPI. Semua pemeriksaan dijalankan melalui CLI; tidak ada endpoint diagnostik publik tambahan.

Verifikasi token pengguna dan membership tenant/pabrik dijelaskan pada [panduan autentikasi backend](backend-authentication.md). Pemeriksaan koneksi Auth settings di sini berbeda dari pemeriksaan access token pengguna.

## Lokasi konfigurasi

Simpan nilai sebenarnya pada `.env` di akar repo. NestJS dan CLI mencari file tersebut berdasarkan lokasi modul, sehingga hasilnya sama ketika dijalankan dari akar repo atau `apps/api`. Environment proses memiliki prioritas lebih tinggi daripada isi file. Pemuat konfigurasi tidak menyalin isi file ke `process.env`.

Untuk setup baru, salin `.env.example` menjadi `.env` tanpa menimpa file lokal yang sudah diisi. `.env` dikecualikan dari Git; `.env.example` hanya berisi placeholder dan nilai development.

| Variabel | Penggunaan |
| --- | --- |
| `APP_NAME` | Nama aplikasi; bawaan `SobatNira` |
| `NODE_ENV` | `development`, `test`, atau `production` |
| `LOG_LEVEL` | `debug`, `info`, `warn`, `error`, atau `silent` |
| `API_HOST`, `API_PORT` | Alamat listen NestJS; bawaan `127.0.0.1:3000` |
| `CORS_ORIGINS` | Origin Flutter web yang diizinkan, dipisahkan koma; bawaan localhost dan loopback pada port 8080 |
| `FRONTEND_ORIGIN` | Fallback jika `CORS_ORIGINS` kosong |
| `AI_BASE_URL` | Tujuan FastAPI; bawaan `http://127.0.0.1:8000` |
| `CONNECTION_TIMEOUT_MS` | Batas waktu operasi pemeriksaan koneksi; bawaan 8000 ms, rentang 100–60000 |
| `AI_TIMEOUT_MS` | Batas waktu request draf AI; bawaan 3000 ms agar tetap di bawah timeout Flutter demo 5000 ms |
| `SUPABASE_URL` | Origin project Supabase |
| `SUPABASE_PUBLISHABLE_KEY` | API key untuk pemeriksaan Supabase Auth |
| `SUPABASE_SECRET_KEY` | Opsional; bila diisi, diperiksa juga melalui Auth settings |
| `DATABASE_URL` | Connection string PostgreSQL, termasuk username, password yang di-URL-encode dan nama database |
| `DATABASE_SSL_CA_FILE` | Opsional; file CA PEM untuk PostgreSQL, absolut atau relatif terhadap akar repo |
| `DATABASE_SSL_CA_PEM` | Opsional; isi lengkap sertifikat CA dalam format PEM untuk deployment. Dipakai jika diisi, sebelum `DATABASE_SSL_CA_FILE`. |
| `REDIS_URL` | URL `redis://` untuk lokal atau `rediss://` untuk TLS; Upstash wajib memakai `rediss://` |
| `R2_ENDPOINT` | Endpoint S3 R2; suffix bucket yang sama dengan `R2_BUCKET_NAME` dinormalisasi otomatis |
| `R2_ACCOUNT_ID` | Opsional; membentuk endpoint R2 bila `R2_ENDPOINT` kosong |
| `R2_REGION` | Bawaan `auto` |
| `R2_BUCKET_NAME` | Bucket yang diperiksa |
| `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` | Kredensial S3 untuk akses bucket |
| `R2_SIGNED_URL_TTL_SECONDS` | Konfigurasi durasi URL sementara untuk integrasi storage berikutnya; bawaan 300 detik |
| `R2_PUBLIC_BASE_URL` | Opsional; origin publik lama untuk memastikan akses anonim ditolak sebelum upload bukti; bukan alamat penyajian foto |

`SUPABASE_PASSWORD` tidak dibaca terpisah: koneksi PostgreSQL mengambil password dari `DATABASE_URL`. Akses foto bukti menggunakan proxy berizin di API; `R2_SIGNED_URL_TTL_SECONDS` belum dipakai untuk jalur foto tersebut. `APP_ENV`, `APP_DEBUG`, `BACKEND_HOST`, `BACKEND_PORT`, dan `API_V1_PREFIX` belum didukung; gunakan nama pada tabel. Endpoint fixture tetap `/health` dan `/demo/draft`; demo dinonaktifkan dengan respons 404 pada production.

Panduan [foto bukti R2](backend-evidence.md) menjelaskan upload, akses privat dan prasyarat menonaktifkan URL/domain publik bucket. Health `HeadBucket` di CLI koneksi hanya memeriksa akses S3, bukan pengaturan domain publik.

Konfigurasi dengan nilai tidak valid atau kelompok kredensial yang hanya terisi sebagian ditolak sebelum API dimulai. Pesan hanya menyebut nama variabel. Kelompok layanan cloud boleh tidak diisi seluruhnya agar starter fixture tetap bisa dijalankan tanpa akun cloud; CLI melaporkannya sebagai `not_configured`.

## Jalankan API dan pemeriksaan

Dari `apps/api`:

```powershell
npm ci
npm test
npm run check:connections
npm run check:connections -- --json
```

Gunakan `npm.cmd` bila PowerShell memblokir `npm.ps1`. Dari akar repo, gunakan `npm --prefix apps/api run check:connections`.

Untuk menjalankan API setelah memeriksa konfigurasi:

```powershell
npm run dev
```

Nyalakan FastAPI di terminal lain dari `apps/ai`:

```powershell
uv sync --locked --python 3.13
uv run --locked uvicorn main:app --host 127.0.0.1 --port 8000
```

Pemeriksaan koneksi tidak dijalankan otomatis pada setiap startup atau request API. `GET /health` tetap hanya menunjukkan proses NestJS hidup. Gunakan CLI untuk memeriksa dependency dan `GET /demo/draft` untuk memeriksa integrasi NestJS ke FastAPI.

Perintah development `npm run dev` dan migrasi OCR `npm run db:migrate:ocr` juga memuat `.env` akar repo ke environment proses melalui Node.js. Ini diperlukan modul intake/review OCR yang membaca `process.env`. Untuk `npm run dev`, nilai dari `apps/api/.env` menimpa nilai yang sama dari `.env` akar repo. Environment yang sudah diberikan terminal tetap memiliki prioritas tertinggi. Pemuat konfigurasi bisnis sendiri tetap tidak mengubah `process.env`.

## Cakupan pemeriksaan

| Layanan | Operasi | Batas pemeriksaan |
| --- | --- | --- |
| Supabase | `GET /auth/v1/settings` untuk publishable key dan secret key bila diisi | Memeriksa Auth/gateway dan penerimaan key; tidak login, membuat pengguna, atau membuktikan izin sesi/RLS |
| PostgreSQL | Koneksi lalu `SELECT 1 AS connected` | Tidak membuat tabel, menjalankan migrasi atau mengubah data |
| R2 | Request S3 bertanda tangan `HeadBucket` | Tidak mengunggah, mengunduh atau menghapus objek; tidak membuktikan izin tulis |
| Redis/Upstash | Autentikasi lalu `PING` | Tidak menulis key atau menjalankan job BullMQ |
| FastAPI | `GET /health` | Mengharapkan `status=ok` dan `service=sobatnira-ai`; tidak menguji provider OCR |

Hasil berisi nama layanan, status, durasi dan pesan aman. Pemeriksaan lain tetap berjalan saat satu layanan gagal. CLI keluar dengan kode `0` hanya bila kelimanya `ok`; kegagalan atau layanan tanpa konfigurasi menghasilkan kode `1`. Koneksi ditutup setelah selesai dan client Redis tidak melakukan retry tanpa batas. Body respons provider, URL, kredensial dan stack trace tidak dicetak.

## PostgreSQL dan sertifikat Supabase

Koneksi PostgreSQL jarak jauh selalu memverifikasi TLS dan hostname. Parameter SSL pada `DATABASE_URL` tidak digunakan untuk menonaktifkan verifikasi. PostgreSQL lokal pada loopback bisa berjalan tanpa TLS; `sslmode=require`, `verify-ca`, `verify-full` atau file CA mengaktifkan TLS pada koneksi lokal juga.

Jika hasil menunjukkan CA belum dipercaya, unduh root certificate dari **Database Settings → SSL Configuration** di dashboard Supabase. Tetapkan, misalnya:

```dotenv
DATABASE_SSL_CA_FILE=.tmp/certs/supabase-prod-ca-2021.crt
```

Folder `.tmp/` dikecualikan dari Git. Sertifikat CA ini bersifat publik dan tidak berisi private key. Untuk sertifikat Supabase production 2021, URL yang tercantum dalam [konfigurasi Studio resmi](https://github.com/supabase/supabase/blob/master/apps/studio/hooks/custom-content/custom-content.json) dapat diunduh dari akar repo:

```powershell
New-Item -ItemType Directory -Force .tmp/certs | Out-Null
Invoke-WebRequest -Uri 'https://supabase-downloads.s3-ap-southeast-1.amazonaws.com/prod/ssl/prod-ca-2021.crt' -OutFile '.tmp/certs/supabase-prod-ca-2021.crt'
```

Gunakan sertifikat yang sesuai dari dashboard jika project/provider memakai CA lain. Lihat [panduan SSL Supabase](https://supabase.com/docs/guides/platform/ssl-enforcement). Jangan menonaktifkan pemeriksaan sertifikat untuk mengatasi error CA.

## Upstash dan FastAPI

BullMQ menggunakan koneksi Redis melalui TLS, bukan REST URL/token. Bentuk URL development cloud:

```dotenv
REDIS_URL=rediss://default:PASSWORD@HOST:6379
```

Isi dengan koneksi dari dashboard Upstash. Pemeriksaan saat ini hanya menguji koneksi Redis; worker dan retry job akan ditambahkan saat alur dokumen dikerjakan. Lihat [panduan BullMQ Upstash](https://upstash.com/docs/redis/integrations/bullmq).

Jika FastAPI gagal dengan koneksi ditolak, jalankan perintah Uvicorn di atas dan ulangi CLI. Jika PostgreSQL tidak terjangkau melalui jaringan IPv4, pilih connection string pooler yang sesuai dari panel Connect Supabase, tanpa mengubah URL pada log.

## Pengujian

`npm test` menggunakan environment sintetis eksplisit dan upstream lokal, sehingga tidak memuat `.env` asli atau menghubungi layanan cloud. Tes mencakup prioritas environment, validasi tanpa membocorkan nilai, CORS, TLS, normalisasi endpoint R2, request pemeriksaan, timeout, kegagalan provider dan penutupan koneksi Redis. Tes API mempertahankan kontrak health/draf dan respons 503 ketika upstream AI gagal.
