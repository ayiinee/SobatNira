# Setup development lokal

Pasang Git dan alat sesuai area yang kamu kerjakan. Untuk menjalankan integrasi, siapkan alat dari ketiga baris.

| Area | Alat | Titik awal |
| --- | --- | --- |
| Flutter | Flutter stable 3.44.6 (Dart 3.12.2) dan Chrome | `apps/mobile/lib/main.dart`. Mulai dari onboarding demo dengan data sintetis. |
| API bisnis | Node.js 24 dengan npm | `apps/api/src/app.module.ts`. Mulai dari kontrak dan validasi dokumen atau data kloter dan batch. |
| AI | Python 3.13 dengan uv | `apps/ai/main.py`. Mulai dari pemetaan field dan fixture draf ekstraksi. |

Untuk Android, gunakan Android SDK dan JDK 21, lalu siapkan emulator atau HP dengan USB debugging. Cek perangkat dan lisensi lewat `flutter doctor -v`.

```sh
git clone https://github.com/ayiinee/SobatNira.git
cd SobatNira
```

Gunakan [panduan kontribusi](contributing.md) untuk membuat branch dan membuka PR. Clone dari GitHub bisa diakses publik. Anggota tim perlu izin tulis dari pemilik repo untuk push branch langsung dan akses ke sumber internal untuk aturan kerja serta desain yang relevan.

## Flutter dengan data sintetis lokal

Jalankan dari akar repo untuk membuka onboarding. Isi nama pengguna dan kata sandi dengan teks sintetis untuk mengakses Beranda, Kloter, Laporan, dan Pengaturan. Sesi demo dan perubahan data lokal kembali ke kondisi awal ketika aplikasi dimulai ulang.

```sh
cd apps/mobile
flutter pub get --enforce-lockfile
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 8080
```

Untuk membuka layar draf sintetis secara mandiri, tambahkan `-t lib/main_demo.dart --dart-define=USE_LOCAL_FIXTURE=true`.

## Kerjakan satu layanan

- **NestJS.** Di `apps/api`, jalankan `npm ci`, `npm test`, lalu `npm run dev`. Cek `http://127.0.0.1:3000/health`. Tes API memakai upstream lokal khusus tes. Endpoint `/demo/draft` memerlukan FastAPI yang sedang berjalan.
- **FastAPI.** Di `apps/ai`, jalankan `uv sync --locked --python 3.13`, `uv run --locked python -m unittest`, lalu `uv run --locked uvicorn main:app --host 127.0.0.1 --port 8000 --reload`. Cek `http://127.0.0.1:8000/docs` dan coba `GET /demo/draft` dari dokumentasi API lokal.

## Jalankan integrasi di tiga terminal

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
flutter run -d chrome -t lib/main_demo.dart --web-hostname 127.0.0.1 --web-port 8080
```

Chrome menampilkan **Draf sintetis**, `DEMO-261114-01`, dan berat 1250 kg. Jika API belum berjalan, nyalakan kembali kedua layanan dan tekan **Coba lagi**.

## Jalankan di Android

Tinjau lisensi yang dilaporkan oleh `flutter doctor --android-licenses`. Buka emulator atau hubungkan HP dengan USB debugging. Jalankan `flutter devices`, lalu gunakan ID yang tampil. Untuk mengerjakan UI dengan draf lokal, jalankan dari `apps/mobile`.

```sh
flutter run -d <device-id>
```

Untuk menguji integrasi dari emulator atau HP, jalankan kedua backend. Dengan satu perangkat Android terhubung, teruskan port API memakai ADB dan jalankan Flutter dengan URL bawaan.

```sh
adb reverse tcp:3000 tcp:3000
flutter run -d <device-id> -t lib/main_demo.dart
```

Jika beberapa perangkat terhubung, gunakan `adb -s <device-id> reverse tcp:3000 tcp:3000`. Emulator juga dapat mengakses loopback laptop menggunakan `10.0.2.2`.

```sh
flutter run -d <emulator-id> -t lib/main_demo.dart --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

Untuk cek layanan langsung, buka `http://127.0.0.1:8000/health`, `http://127.0.0.1:3000/health`, dan `http://127.0.0.1:3000/demo/draft`. API dapat mengubah port dengan `API_PORT` dan tujuan AI dengan `AI_BASE_URL`. Jika port API diganti, sesuaikan `--dart-define=API_BASE_URL=...` untuk Flutter. Web memakai port 8080 agar origin sesuai konfigurasi lokal API.

## Tes sebelum mengambil tugas

| Direktori | Perintah | Cakupan |
| --- | --- | --- |
| `apps/ai` | `uv run --locked python -m unittest` | Health dan payload fixture FastAPI |
| `apps/api` | `npm test` | Build TypeScript, health HTTP, integrasi dengan upstream tes, respons 503 jika AI gagal |
| `apps/mobile` | `flutter analyze`, `flutter test` | Analisis statis, alur Beranda, Kloter, Laporan, Pengaturan, serta coba ulang saat API gagal |

Setup ini memakai satu fixture yang dilayani FastAPI, diteruskan NestJS, dan ditampilkan Flutter. PostgreSQL/Supabase, Redis, WhatsApp, R2 dan provider OCR belum dibutuhkan untuk smoke test ini.

Untuk pekerjaan intake WhatsApp, OCR, atau antrean Pekerjaan, rujuk PRD AI Engineering melalui indeks dokumen internal tim. Kriteria ujinya mencakup dua jenis nota, revisi foto, konfirmasi operator, dan peninjauan mobile. Tes fixture pada setup ini membuktikan koneksi ketiga aplikasi.

## Jika setup tersendat

- Instal dependency dari direktori masing-masing. Jalankan `npm.cmd` sebagai pengganti `npm` bila PowerShell memblokir `npm.ps1`.
- Jalankan `flutter doctor -v` untuk masalah SDK, Chrome atau Android. Gunakan browser lokal untuk verifikasi awal jika emulator belum siap.
- Jika C: sempit di Windows, gunakan cache di D:. Contoh untuk PowerShell sebelum instalasi dependency atau build Android.

  ```powershell
  $env:PUB_CACHE = 'D:\DevCache\pub'
  $env:GRADLE_USER_HOME = 'D:\DevCache\gradle'
  $env:UV_CACHE_DIR = 'D:\DevCache\uv'
  $env:npm_config_cache = 'D:\DevCache\npm'
  ```

- Jika ekstensi Gradle VS Code memakai Java 8, tutup VS Code, set `JAVA_HOME` ke folder JDK 21, lalu buka ulang VS Code dari PowerShell yang sama. Untuk instalasi Android Studio di lokasi default, folder JDK 21 yang terpasang di mesin audit adalah `C:\Program Files\Android\Android Studio\jbr`.
- Health NestJS dapat sukses ketika FastAPI mati. Periksa `/demo/draft` untuk mengecek transaksi antarservice.
- API lokal mendengarkan loopback. Android emulator menggunakan host khusus `10.0.2.2`. Panduan ini mengasumsikan API dan Flutter berjalan pada mesin yang sama.
