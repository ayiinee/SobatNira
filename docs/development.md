# Setup development lokal

Gunakan [prosedur uji penerimaan lokal](ai/README.md#mode-lokal-sintetis) untuk menyamakan versi, fixture, migrasi dan hasil uji antaranggota tim. Prosedur ini membangun `apps/mobile/lib/main.dart` dan menyajikan Flutter, login sintetis, serta API NestJS di `http://127.0.0.1:8000/`. OCR berjalan sebagai layanan internal.

### Penyimpanan menu Pengaturan

Form sesi menggunakan widget Pengaturan tim dan kembali ke fixture ketika aplikasi dimulai ulang. Pada mode terhubung, menu yang memerlukan kontrak tambahan tampil dengan status **Belum tersedia**. Gunakan mode lokal untuk meninjau bentuk form tersebut.

| Menu | Penyimpanan saat ini | Kontrak atau keputusan yang dibutuhkan |
| --- | --- | --- |
| Identitas pabrik | Nama pabrik dibaca dari sesi API. Form identitas tersimpan di sesi lokal. | Endpoint edit nama, kode, cabang dan zona waktu, serta hak edit. |
| Fasilitas Produksi | Sesi lokal. API master memiliki daftar dan tambah wajan dengan kode dan nama. | Kontrak kapasitas, aktivasi, pembaruan dan pemakaian master saat memvalidasi pemasakan. |
| Pegawai & WhatsApp | API pabrik untuk nama, nomor dan status aktif operator. | Penugasan per operator pada form tim memerlukan kontrak sendiri. |
| Shift kerja | Sesi lokal. | Definisi shift, waktu lintas tengah malam dan pengaitnya ke batch. |
| Hak akses & pengguna | Sesi lokal. Membership yang dipakai login dan otorisasi dibaca dari API. | Undangan, perubahan role, pencabutan akses dan siapa yang berwenang. |
| Aturan produksi | Sesi lokal. API master memiliki versi konfigurasi awal. | Aturan campuran, masak ulang, batas volume serta aktivasi aturan yang berlaku. |
| Grade produk | Sesi lokal. API master memiliki daftar dan tambah kode/nama. Grade resmi dicatat pada batch. | Pembaruan grade dan harga efektif, termasuk penerapannya pada snapshot dan batch lama. |
| Bahan tambahan (BTP) | Sesi lokal. API master memiliki daftar dan tambah kode/nama. | Satuan, takaran, status aktif dan cara pencatatan pemakaian pada batch. |
| Formulir produksi | Sesi lokal. OCR memakai skema yang ikut versi repositori. | Kontrak versi pemetaan field wajib dan alias yang boleh dikelola per pabrik. |
| Harga & Biaya | Sesi lokal untuk menu ini dan pintasan Biaya Ops. Harga per batch dan biaya per kloter memakai API. | Harga sumber, komponen biaya, hak melihat harga/biaya, tanggal berlaku, serta riwayat koreksi. |
| Pemasok | API katalog pabrik. | — |
| Jenis tebu | API katalog pabrik. | — |
| Keluar | Mengakhiri sesi pada aplikasi. | — |

Endpoint awal master produksi menyimpan kode dan nama atau versi draf. Implementasi lama memakai memori atau adapter Supabase. Untuk menghubungkannya ke form tim, diperlukan penyimpanan PostgreSQL yang dipakai pemasakan resmi dan kontrak untuk field yang ditampilkan. Lihat [pemeriksaan akses dan konfigurasi backend](backend-authentication.md) serta [implementasi produksi](backend-production-implementation.md).

Pasang Git dan alat sesuai area yang kamu kerjakan. Untuk menjalankan integrasi, siapkan alat dari ketiga baris.

| Area | Alat | Titik awal |
| --- | --- | --- |
| Flutter | Flutter stable 3.44.6 (Dart 3.12.2) dan Chrome | `apps/mobile/lib/main.dart`. Siapkan konfigurasi API dan login atau pilih demo offline. |
| API bisnis | Node.js 24 dengan npm | `apps/api/src/app.module.ts`. Mulai dari kontrak dan validasi dokumen atau data kloter dan batch. |
| AI | Python 3.13 dengan uv | `apps/ai/main.py`. Mulai dari pemetaan field dan fixture draf ekstraksi. |

Untuk Android, gunakan Android SDK dan JDK 21, lalu siapkan emulator atau HP dengan USB debugging. Cek perangkat dan lisensi lewat `flutter doctor -v`.

```sh
git clone https://github.com/ayiinee/SobatNira.git
cd SobatNira
```

Gunakan [panduan kontribusi](contributing.md) untuk membuat branch dan membuka PR. Clone dari GitHub bisa diakses publik. Anggota tim perlu izin tulis dari pemilik repo untuk push branch langsung dan akses ke sumber internal untuk aturan kerja serta desain yang relevan.

## Flutter dengan data sintetis lokal

Untuk menjalankan Chrome dari Command Prompt di akar repo dengan hot reload otomatis saat file Dart berubah:

```bat
dev-mobile.cmd
```

Perintah ini menjalankan fixture desain offline melalui `lib/main.dart` pada port 8085 dan memantau `apps/mobile/lib`. Perubahan dari editor atau alat lain memicu hot reload setelah jeda 0,7 detik. Hentikan proses dengan Ctrl+C. Perubahan yang membutuhkan hot restart memerlukan menjalankan ulang sesi ini.

Jalankan dari akar repo untuk langsung membuka Beranda, Kloter, Laporan, dan Pengaturan. Onboarding dan login demo dinonaktifkan sementara. Perubahan data lokal kembali ke kondisi awal ketika aplikasi dimulai ulang.

Pada demo lokal, batch yang tervalidasi terkunci untuk edit. Gunakan ikon silang **Batalkan validasi batch** di sebelah tombol status untuk membuka koreksi; batch kembali ke status perlu ditinjau (kuning). Pembatalan hanya berlaku untuk batch yang dipilih. Nilai yang sudah dicatat tetap disimpan selama sesi demo. Alur ini belum mengubah pengesahan dokumen atau stok pada API.

Pintasan **Laba** dan **Rekap** di Beranda membuka laporan siap cetak. Keduanya mengambil rincian dan periode dari data Laporan yang sama; tidak ada pencatatan tambahan. Total pada dokumen dijumlahkan dari baris yang diekspor. **Cetak laporan** membuka dialog cetak browser/sistem dengan dokumen A4; **Simpan PDF** mengunduh file di web atau membuka menu berbagi PDF di Android. PDF memakai font Inter lokal, tabel yang berlanjut antarhalaman, nomor halaman, dan penanda data sintetis. Pintasan **Biaya Ops** membuka form Harga & Biaya yang sama dengan Pengaturan, dengan biaya operasional di bagian atas. Penyimpanan dan pembatalan draf menggunakan state sesi yang sama. **Bantuan** menyediakan pesan hingga 1.500 karakter dan membuka WhatsApp ke 085337236836 dengan draf terisi langsung ke aplikasi WhatsApp pada Android. Browser memakai tautan universal `wa.me/6285337236836` agar WhatsApp menentukan cara membuka chat. Tautan yang sama menjadi cadangan pada Android. Pengguna menekan Kirim di WhatsApp untuk mengirim pesan; aplikasi tidak menandai pesan sebagai terkirim hanya karena WhatsApp terbuka. Pesan kosong ditolak dan draf tetap tersedia jika WhatsApp gagal dibuka.

Rekap menggabungkan catatan berdasarkan kode kloter: identitas tebu, kendaraan dan rincian batch dari `DemoProduction`, lalu gula final, rendemen dan margin dari `DemoAnalytics`. Kloter yang hanya tersedia di salah satu sumber tetap ditampilkan sesuai periode. Nilai yang belum tersedia ditandai `-`, dan ringkasan menyebut jumlah kloter yang sudah memiliki gula final atau margin. Gula final kloter tidak disamakan dengan hasil fisik atau berat grade batch; masing-masing tetap mengikuti catatan sumbernya. Rincian batch mencakup sesi, Brix, nira, gamping, hasil fisik, grade, jam turun, dan status validasi. Nomor wajan belum ada di model demo dan tidak diturunkan dari nomor batch. Aplikasi memakai bagian yang dapat dibuka-tutup; PDF rekap memakai A4 mendatar dan mencetak seluruh rinciannya. Snapshot cetak tidak berubah jika sumber diedit setelah ekspor dimulai. Penggabungan ini hanya untuk demo; kontrak API dan kalkulasi produksi resmi tidak diubah.

```sh
cd apps/mobile
flutter pub get --enforce-lockfile
flutter run -d chrome -t lib/main.dart --web-hostname 127.0.0.1 --web-port 8085 --dart-define=SOBATNIRA_MODE=demo
```

Untuk menguji nota sintetis melalui Pekerjaan dan pembukuan resmi, ikuti [smoke test lokal](ai/README.md#mode-lokal-sintetis).

## Flutter dengan Supabase dan backend dari .env

Pastikan `.env` di akar repo sudah berisi `SUPABASE_URL` dan `SUPABASE_PUBLISHABLE_KEY`. Isi `API_BASE_URL` dengan URL dasar layanan Railway untuk memakai backend yang sudah di-deploy. Untuk backend lokal, ikuti [konfigurasi backend](backend-configuration.md) dan jalankan `npm run dev` dari `apps/api`.

Dari akar repo jalankan:

```powershell
.\dev-mobile.cmd --connected
```

Perintah ini membuka Chrome di `http://127.0.0.1:8080` dengan layar login Supabase. Setelah masuk memakai akun Supabase yang memiliki membership pabrik, Kloter dan Pekerjaan mengambil data dari NestJS. [Panduan akses backend](backend-authentication.md) menjelaskan migrasi dan pemberian akses pabrik. Beranda, Laporan, Laba dan Rekap pada mode connected memakai [laporan produksi terhubung](mobile-production-reports.md); mode demo tetap memakai fixture sintetis lokal.

Launcher membaca `.env` menggunakan Node.js 24 dan membuat `.tmp/mobile/public-defines.json` yang diabaikan Git. Hanya `SOBATNIRA_MODE`, `API_BASE_URL`, `SUPABASE_URL`, dan publishable/anon key yang disertakan. Jangan memberikan `.env` backend langsung ke `--dart-define-from-file` karena semua nilainya dapat masuk ke aplikasi klien.

Alamat API mengikuti `API_BASE_URL` bila diisi, atau `API_HOST` dan `API_PORT` (bawaan `http://127.0.0.1:3000`). Untuk mengganti port Flutter, daftarkan origin yang sesuai di `CORS_ORIGINS` dan mulai ulang NestJS. Perintah tanpa flag mode dan perintah dengan `--demo` sama-sama membuka fixture offline.

Untuk membuat APK Android terhubung, buat konfigurasi publik dari akar repo, lalu build dari `apps/mobile`:

```powershell
node .\tools\mobile_config.mjs
cd apps/mobile
flutter build apk --release --dart-define-from-file=../../.tmp/mobile/public-defines.json
```

APK dihasilkan di `apps/mobile/build/app/outputs/flutter-apk/app-release.apk`. Konfigurasi Android pada repo menggunakan tanda tangan debug untuk build release lokal.

Untuk mengisi database development dengan data sintetis, jalankan dari `apps/api`:

```powershell
npm.cmd run db:migrate
npm.cmd run db:migrate:ocr
npm.cmd run db:seed:demo
```

Seeder memerlukan `NODE_ENV=development` serta `SUPABASE_SECRET_KEY` untuk membuat akun Auth sintetis `admin.demo@example.invalid`. Seeder mengonfirmasi akun ini melalui Admin API tanpa mengirim email, lalu memberi akses admin hanya ke **Pabrik Demo Sintetis**. Seeder membuat satu usaha, satu pabrik, dua pemasok, dua jenis tebu dan tiga kloter dengan ID tetap, sehingga pengulangan tidak menggandakan data. Stok tetap nol sampai nota disahkan melalui alur bisnis.

Email dan kata sandi acak disimpan di `.tmp/mobile/demo-login.json`, di luar Git dan di luar konfigurasi publik Flutter. Gunakan akun tersebut pada layar login. Seeder menolak mengambil alih akun lain yang memakai email demo; akun yang dinonaktifkan tidak diaktifkan ulang. Jika file login hilang, pengulangan seeder mengganti kata sandi khusus akun demo yang ditandai oleh seeder ini.

## Kerjakan satu layanan

- **NestJS.** Di `apps/api`, jalankan `npm ci`, `npm test`, lalu `npm run dev`. Cek `http://127.0.0.1:3000/health`. Tes API memakai upstream lokal khusus tes. Endpoint `/demo/draft` memerlukan FastAPI yang sedang berjalan.
- **FastAPI.** Di `apps/ai`, jalankan `uv sync --locked --python 3.13`, `uv run --locked python -m unittest`, lalu `uv run --locked uvicorn main:app --host 127.0.0.1 --port 8000 --reload`. Cek `http://127.0.0.1:8000/docs` dan coba `GET /demo/draft` dari dokumentasi API lokal.

### Environment API

Template environment berada di `apps/api/.env.example`. Salin menjadi `apps/api/.env`, lalu isi kredensial saat integrasi layanan Backend A dimulai. Starter lokal hanya memakai:

```env
API_PORT=3000
AI_BASE_URL=http://127.0.0.1:8000
DATA_MODE=fixture
```

`npm run dev` memuat `apps/api/.env` otomatis. File `.env` tidak boleh di-commit; `.env.example` aman dibagikan tanpa nilai rahasia.

Endpoint produksi B1 memakai header identitas development saat `NODE_ENV=development`: `x-dev-user-id`, `x-dev-tenant-id`, `x-dev-factory-id`, dan `x-dev-role` (`admin` atau `owner`). Mode `fixture` memakai data sintetis; mode `supabase` memakai migrasi `apps/api/migrations/001_b1_production.sql`.

Endpoint tambahan B1: `GET/POST /production-masters/{pans,grades,additives,configs,prices}`, `GET /batches/nira/:kloterId/availability`, dan `GET /batches/closure-check/:kloterId`. B2 menyediakan `GET /stock/sugar`, `POST /stock/sugar/movements`, `POST /stock/sugar/corrections`, dan alokasi `POST /batches/:id/economics/allocation`. B3 menyediakan `GET /dashboard/production`, `GET /analytics/production`, dan `GET /exports/batches.csv`. Perubahan master, stok, dan produksi membutuhkan role `admin`; pembacaan dapat memakai `owner`.

Mode `supabase` memakai tabel stok/alokasi/audit dari migrasi yang sama. Isi `DEFAULT_PRODUCTION_CONFIG_ID` dan `DEFAULT_PRICE_VERSION_ID` sebelum membuat batch; operasi koreksi stok selalu membuat movement baru dan audit event.

## Jalankan integrasi di tiga terminal

Untuk menghubungkan kredensial pada `.env` di akar repo ke Supabase, PostgreSQL, R2 dan Redis/Upstash, ikuti [konfigurasi backend dan pemeriksaan koneksi](backend-configuration.md). Jalankan `npm run check:connections` dari `apps/api` setelah FastAPI aktif. Layanan cloud tetap opsional untuk smoke test fixture di bawah.

Untuk endpoint bisnis yang memakai login, jalankan migrasi dan hubungkan membership sesuai [panduan autentikasi dan akses backend](backend-authentication.md). Endpoint baru memerlukan kebijakan akses eksplisit; `/health` dan demo sintetis development tetap dapat dipakai tanpa login.

Modul [data dasar pemasok dan kloter](backend-production-basics.md) dapat dikembangkan sebelum onboarding selesai. Jalankan `npm run test:production-db` dari `apps/api` untuk memeriksa alur HTTP dengan PostgreSQL dan fixture sintetis yang selalu di-rollback.

Alur [dokumen penerimaan sampai pengesahan](backend-intake-documents.md) memakai draf sintetis sambil menunggu OCR. Setelah migrasi, jalankan `npm run test:intake-db` untuk memeriksa revisi, konfirmasi, pengesahan, audit, stok masuk dan pengesahan bersamaan tanpa onboarding.

Modul [foto bukti R2](backend-evidence.md) menghubungkan foto ke revisi dokumen dan menyajikannya melalui API berizin. `npm run test:evidence-db` memakai S3 tiruan; `npm run test:evidence-r2` menguji upload/baca dengan R2 nyata serta membersihkan fixture. Bucket bukti wajib privat.

Modul [penggilingan dari nota hasil gabungan](backend-milling-documents.md) memakai draf sintetis untuk total nira dan rincian batch. Pengesahan mengurangi seluruh stok tebu kloter dari penerimaan sah dan mencatat nira dalam satu transaksi. Jalankan `npm run test:milling-db` untuk memeriksa alur, pembatasan akses, rollback dan konkurensi dengan PostgreSQL.

Gunakan [kontrak nira dan penutupan kloter](backend-juice-and-closure.md) untuk adapter Backend B. Jalankan `npm run test:juice-db` setelah migrasi untuk memeriksa reservasi, transfer, dan penutupan dengan fixture Backend B.

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
flutter run -d chrome -t lib/main.dart --web-hostname 127.0.0.1 --web-port 8080 --dart-define-from-file=../../.tmp/mobile/public-defines.json
```

Gunakan file konfigurasi publik dari launcher terhubung. Untuk stub login dan nota sintetis dari adapter WhatsApp, gunakan perintah Flutter di [smoke test lokal](ai/README.md#mode-lokal-sintetis).

## Jalankan di Android

Tinjau lisensi yang dilaporkan oleh `flutter doctor --android-licenses`. Buka emulator atau hubungkan HP dengan USB debugging. Jalankan `flutter devices`, lalu gunakan ID yang tampil. Untuk mengerjakan UI dengan draf lokal, jalankan dari `apps/mobile`.

```sh
flutter run -d <device-id> -t lib/main.dart --dart-define=SOBATNIRA_MODE=demo
```

Untuk menguji integrasi dari emulator atau HP, jalankan kedua backend. Dengan satu perangkat Android terhubung, teruskan port API memakai ADB dan jalankan Flutter dengan URL bawaan.

```sh
adb reverse tcp:3000 tcp:3000
flutter run -d <device-id> -t lib/main.dart --dart-define-from-file=../../.tmp/mobile/public-defines.json
```

Jika beberapa perangkat terhubung, gunakan `adb -s <device-id> reverse tcp:3000 tcp:3000`. Emulator juga dapat mengakses loopback laptop menggunakan `10.0.2.2`.

```sh
flutter run -d <emulator-id> -t lib/main.dart --dart-define-from-file=../../.tmp/mobile/public-defines.json --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

Untuk cek layanan langsung, buka `http://127.0.0.1:8000/health`, `http://127.0.0.1:3000/health`, dan `http://127.0.0.1:3000/demo/draft`. API dapat mengubah port dengan `API_PORT` dan tujuan AI dengan `AI_BASE_URL`. Jika port API diganti, sesuaikan `--dart-define=API_BASE_URL=...` untuk Flutter. Web memakai port 8080 agar origin sesuai konfigurasi lokal API.

## Tes sebelum mengambil tugas

| Direktori | Perintah | Cakupan |
| --- | --- | --- |
| `apps/ai` | `uv run --locked python -m unittest` | Health dan payload fixture FastAPI |
| `apps/api` | `npm test` | Build TypeScript, health HTTP, integrasi dengan upstream tes, respons 503 jika AI gagal |
| `apps/mobile` | `flutter analyze`, `flutter test` | Analisis statis, alur Beranda, Kloter, Laporan, Pengaturan, serta coba ulang saat API gagal |

Setup ini memakai satu fixture yang dilayani FastAPI, diteruskan NestJS, dan ditampilkan Flutter. PostgreSQL/Supabase, Redis, WhatsApp, R2 dan provider OCR belum dibutuhkan untuk smoke test ini.

Untuk intake WhatsApp, OCR, dan antrean Pekerjaan, ikuti [panduan setup dan smoke test AI](ai/README.md). Alur tersebut memakai PostgreSQL, PaddleOCR dan Flutter dengan fixture foto untuk dua jenis nota.

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

Pada Bantuan versi web, tautan WhatsApp dibuka melalui navigasi browser pada tab yang sama agar tidak bergantung pada pop-up atau registrasi plugin setelah hot reload. Navbar Bantuan disembunyikan saat kolom pesan aktif dan muncul kembali setelah fokus dilepas; keyboard dengan inset juga menyembunyikan navbar pada halaman lain.
