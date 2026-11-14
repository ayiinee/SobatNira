# Setup development lokal

Gunakan Git, Node.js 24 dengan npm, Python 3.13 dengan uv, Flutter stable 3.44.6 (Dart 3.12.2), dan Chrome. Untuk Android, pasang Android SDK dan siapkan emulator melalui Android Studio. Cek instalasi Flutter dengan `flutter doctor`.

```sh
git clone https://github.com/ayiinee/SobatNira.git
cd SobatNira
```

## Jalankan di tiga terminal

**1. FastAPI** dari akar repo.

```sh
cd apps/ai
uv sync --locked --python 3.13
uv run --locked uvicorn main:app --host 127.0.0.1 --port 8000
```

**2. NestJS** dari akar repo.

```sh
cd apps/api
npm ci
npm run dev
```

**3. Flutter** dari akar repo.

```sh
cd apps/mobile
flutter pub get --enforce-lockfile
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 8080
```

Chrome menampilkan **Draf sintetis**, `DEMO-261114-01`, dan berat 1250 kg. Jika API belum berjalan, nyalakan kembali kedua layanan dan tekan **Coba lagi**.

Untuk Android emulator, selesaikan persyaratan Android SDK yang dilaporkan `flutter doctor`, jalankan `flutter devices`, lalu ganti `<emulator-id>` dengan ID yang tampil.

```sh
flutter run -d <emulator-id> --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

Untuk cek layanan langsung, buka `http://127.0.0.1:8000/health`, `http://127.0.0.1:3000/health`, dan `http://127.0.0.1:3000/demo/draft`. API dapat mengubah port dengan `API_PORT` dan tujuan AI dengan `AI_BASE_URL`. Jika port API diganti, sesuaikan `--dart-define=API_BASE_URL=...` untuk Flutter. Web memakai port 8080 agar origin sesuai konfigurasi lokal API.

## Tes sebelum mengambil tugas

| Direktori | Perintah | Cakupan |
| --- | --- | --- |
| `apps/ai` | `uv run --locked python -m unittest` | Health dan payload fixture FastAPI |
| `apps/api` | `npm test` | Build TypeScript, health HTTP, integrasi dengan upstream tes, respons 503 jika AI gagal |
| `apps/mobile` | `flutter analyze`, `flutter test` | Analisis statis, tampilkan fixture dan coba ulang saat API gagal |

Setup ini memakai satu fixture yang dilayani FastAPI, diteruskan NestJS, dan ditampilkan Flutter. PostgreSQL/Supabase, Redis, WhatsApp, R2 dan provider OCR belum dibutuhkan untuk smoke test ini.

## Jika setup tersendat

- Instal dependency dari direktori masing-masing. Jalankan `npm.cmd` sebagai pengganti `npm` bila PowerShell memblokir `npm.ps1`.
- Jalankan `flutter doctor -v` untuk masalah SDK, Chrome atau Android. Gunakan browser lokal untuk verifikasi awal jika emulator belum siap.
- Health NestJS dapat sukses ketika FastAPI mati. Periksa `/demo/draft` untuk mengecek transaksi antarservice.
- API lokal mendengarkan loopback. Android emulator menggunakan host khusus `10.0.2.2`. Panduan ini mengasumsikan API dan Flutter berjalan pada mesin yang sama.
