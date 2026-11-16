# SobatNira

## Peta kode

- `apps/mobile` berisi aplikasi Flutter untuk admin dan owner.
- `apps/api` berisi API bisnis NestJS. Validasi, otorisasi, dan kalkulasi resmi berada di sini.
- `apps/ai` berisi layanan internal FastAPI yang menghasilkan draf ekstraksi dan keluaran AI untuk NestJS.

## Acuan keputusan

- Jika tersedia di workspace, mulai dari [indeks dokumen internal](docs/internal/index.md) dan baca dokumen yang terkait dengan tugas. Gunakan register keputusan untuk mengecek status aturan produksi. Jika acuan yang dibutuhkan belum tersedia atau keputusannya masih terbuka, klarifikasi dengan tim sebelum menetapkannya di kode.
- Baca [acuan proyek](docs/project-overview.md) untuk memahami istilah produksi, tanggung jawab layanan, dan status implementasi di repo.
- Perlakukan fixture sebagai data sintetis. Simpan kredensial, nota asli, data mitra, dan dokumen internal di luar Git.

## Pengembangan dan verifikasi

- Ikuti [panduan setup lokal](docs/development.md) untuk instalasi, menjalankan layanan, dan menyiapkan fixture.
- Ikuti [panduan kontribusi](docs/contributing.md) untuk struktur folder, nama branch dan commit, serta proses PR. Jika lokasi penyimpanan di Windows bisa dipilih, gunakan D: saat tersedia.
- Periksa komponen yang diubah dari direktorinya. Gunakan `flutter analyze` dan `flutter test` untuk Flutter, `npm test` untuk NestJS, atau `uv run --locked python -m unittest` untuk FastAPI.
- Jika perubahan menyentuh kontrak antar layanan, verifikasi alur yang terdampak dengan data sintetis. Untuk alur yang dimulai di aplikasi, cek dari Flutter hingga API terkait.
