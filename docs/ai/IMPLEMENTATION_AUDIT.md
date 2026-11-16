# Audit implementasi AI SobatNira

Baseline `1b3348f`, 16 November 2026. Spesifikasi lengkap dan register keputusan tersedia pada indeks internal workspace. Dokumen ini mendeskripsikan kondisi repo saat audit.

| Komponen | Ditemukan | Gap dan risiko |
| --- | --- | --- |
| NestJS | NestJS 11.2.10, Node.js 24, `/health` dan proxy `/demo/draft`, tes HTTP upstream | Belum ada DTO workflow, database, otorisasi, penyimpanan gambar, atau antrean. Percobaan ulang dan konkurensi harus dipastikan pada transaksi PostgreSQL. |
| FastAPI | Python 3.13 dengan uv, `/health` dan fixture `/demo/draft`, tes unit | Belum ada OCR, klasifikasi, parser, penyimpanan atau panggilan model. Akurasi dan template nyata menunggu sampel anonim yang disetujui. |
| Flutter | Flutter 3.44.6, simulasi lokal Beranda, Kloter, Laporan dan Pengaturan, demo HTTP terpisah | Belum ada Pekerjaan yang membaca API atau sesi login produksi. Simulasi lokal bukan sumber data dan aturan produksi. |
| Infrastruktur | CI untuk tiga aplikasi dan lockfile masing-masing | Belum ada migration, Supabase/Auth, OpenClaw/Baileys, R2, Redis/BullMQ, atau konfigurasi provider. Kredensial live tidak terdeteksi di environment audit. |

## Rekonsiliasi keputusan

- PRD AI terbaru menggunakan Baileys melalui OpenClaw. WhatsApp Cloud API dalam arsitektur lama bersifat historis untuk alur ini.
- Proses fisik tetap menjadi konteks domain. Kontrak OCR aktif mencakup `TRUCK_ARRIVAL_NOTE` dan `PRODUCTION_NOTE`. Nota produksi dapat memiliki beberapa revisi.
- Simulasi UI memakai angka ilustratif. Kontrak ekstraksi baru mengikuti PRD untuk kg pada `ISI` dan `HASIL`, `CUSTOM_MEASURE` pada gamping, serta tahap Brix `UNKNOWN`.
- Label tebu, kolom tertutup, penyelarasan baris ambigu, dan retensi media tetap memerlukan konfirmasi. Pertahankan bukti dan nilai mentah, gunakan status eksplisit, dan eskalasi kecocokan yang meragukan.

## Urutan kerja

1. Validasi kontrak JSON bersama dari payload sintetis. Tambahkan migration PostgreSQL berversi untuk identitas operator, media, revisi, pekerjaan, review, dan audit.
2. Hubungkan bridge intake dan penyimpanan privat. Otorisasi operator di NestJS dan buat pekerjaan ekstraksi secara transaksional.
3. Hubungkan endpoint OCR internal dengan validasi gambar dan parser deterministik. Evaluasi PaddleOCR dan Gemini terpisah dari pengujian workflow sintetis.
4. Kaitkan koreksi, konfirmasi, dan review dengan revisi tertentu. Uji alur dari NestJS ke FastAPI dan Flutter dengan data sintetis.

Dependensi awal meliputi driver PostgreSQL dan validator JSON Schema di NestJS serta validator JSON Schema dan decoder gambar di FastAPI. Adapter provider dipisahkan agar setup demo lama dan CI dapat berjalan tanpa akun atau kredensial eksternal.
