# Verifikasi end-to-end

## Lingkungan dan reproduksi

Gunakan [prosedur acceptance otomatis](README.md#acceptance-otomatis-di-chrome) dengan Flutter entry point tim, satu origin 8000, database PostgreSQL per putaran, OCR PaddleCPU, login dan WhatsApp simulasi, serta media privat lokal. Gunakan `node --test test/integration/owner-agent-database.test.cjs` dari `apps/api` setelah build dan migrasi pada database fixture untuk mengulang uji owner dan recovery.

## Acceptance insight produksi

Acceptance menanyakan total produksi, distribusi grade, dan kontribusi terbesar melalui adapter OpenClaw. Pertanyaan tanpa basis meminta klarifikasi sambil menampilkan total dan grade. Dengan basis tanggal penerimaan kloter batch, hasilnya 40.000 mL dari `OCR-A-UJI`. Total Flutter, PostgreSQL, PDF dan XLSX owner cocok pada 25 kg grade A dan Rp375.000 margin sementara. Fixture mencatat 50.000 mL nira tersisa dan menolak akses lintas pabrik serta pengesahan oleh owner.

Build web dari `apps/mobile/lib/main.dart` memakai SHA-256 `f7f5908d26f827fc8e55c4d4e753135efc7c8bc0f18f2a1d9e04d7a17af7c382`, sama dengan bundel acuan. Pengaturan cocok per piksel dengan acuan. Detail Kloter dan Laporan memakai tata letak serta angka yang sama, dengan perbedaan kecil pada posisi render. Dasar Git yang diuji adalah `ca91d1b79c0a14b301d1f16a796a43ad86db013e` dengan perubahan lokal. Verifikasi rilis dari SHA integrasi di dua clone bersih masih terbuka.

Dua putaran browser dari salinan B memakai database kosong terpisah. Bukti `output/playwright/insight-verified` dan `output/playwright/insight-final-b` cocok pada JSON acceptance, teks PDF Flutter, dan sel bisnis XLSX owner. Perbandingan XLSX mengabaikan ID snapshot yang unik per database. Putaran pertama mendahului penghematan panggilan model. Putaran kedua memakai sumber terakhir dengan SHA-256 `2207494492ce2829fc37be223e53d2970b70bff9f8639b50e3d1d819212379b3` untuk 374 file non-dokumentasi. Percobaan salinan A mencapai OCR, lalu berhenti karena pemanggilan langsung Node tidak menyetel konteks npm yang dibutuhkan launcher Chrome. Uji browser final memakai perintah resmi `npm.cmd run local:stack -- --web --acceptance-browser`.

Tes PostgreSQL terarah mengubah satu debit di dalam fixture untuk membuktikan peringkat ditahan saat data berbeda dari volume batch sah. Tes memakai OpenRouter stub untuk pemilihan intent dan penjelasan. Intent yang sudah dikenal langsung memakai NestJS. Fallback hanya mendapat kata operasi yang diizinkan atau status kelengkapan. Tes transport R2 memakai SDK stub untuk memeriksa penyimpanan privat, tulis ulang idempoten, dan penolakan stream dengan ukuran yang salah.

Suite NestJS lulus 79 tes dengan `TEST_DATABASE_URL` lokal dan FastAPI lulus 16 tes. Integrasi lulus 16 tes pada putaran pertama, termasuk kontrak Langflow REST stub. Tes akses PostgreSQL berhasil saat diulang setelah menambahkan `created_at` dan `updated_at` bertipe `timestamptz` pada `auth.users` sintetis. Tabel fixture launcher memiliki skema Auth minimal. Flutter Analyze bersih dan suite Flutter lulus 89 tes dengan dua fixture backend opsional dilewati. Tes Supabase dan R2 nyata memerlukan staging tersendiri.

Empat foto sintetis pada putaran terakhir memberi median pengiriman balasan awal adapter 39 ms dan median ekstraksi PaddleOCR 51,1 detik. Kiriman duplikat dikeluarkan dari perhitungan. P95 memerlukan sampel independen yang memadai. Latensi pengiriman perangkat dan waktu review manual memerlukan pilot.

## Hasil acceptance 20 November 2026

Dua putaran lulus pada dua salinan sumber sementara dan dua database kosong di PostgreSQL lokal. Sumber aplikasi kedua salinan cocok dengan perubahan lokal berbasis `ca91d1b79c0a14b301d1f16a796a43ad86db013e`. Fingerprint 369 file non-dokumentasi pada repositori, salinan A, dan salinan B sama, yaitu `b872a8a8d8a818b2450c23138142a3960bb9b0492039c2ba98a7db1e41ebe841`. Dua build independen `main.dart.js` juga memiliki hash sama, `F7F5908D26F827FC8E55C4D4E753135EFC7C8BC0F18F2A1D9E04D7A17AF7C382`.

Kedua putaran menghasilkan bukti JSON dan teks PDF Flutter yang identik. Masing-masing menyelesaikan tiga pengesahan, mencatat satu batch, mempertahankan 50 L stok sesudah konsumsi 40 L, lalu menghasilkan 25 kg grade A dan Rp375.000 margin sementara. Sel bisnis XLSX sama setelah ID snapshot server dikeluarkan dari pembandingan. Setiap PDF owner memuat nilai yang sama dengan snapshot. Tangkapan layar Pengaturan identik per piksel. Detail Kloter dan Laporan memakai susunan dan angka yang sama dengan pergeseran render kecil pada tangkapan layar. Bukti lokal tersimpan di `output/playwright/master-verified-a` dan `output/playwright/master-verified-b`.

Percobaan sebelumnya berhenti saat kompilasi bersamaan dengan OCR menekan memori, dan saat ruang database D: habis. Putaran final menggunakan cluster sementara di C: dan berjalan berurutan. Automasi login juga diperbaiki agar Flutter memberi fokus pada field sebelum pengisian. Database yang sudah ada dipertahankan.

## Bukti per alur

| Alur | Status bukti |
| --- | --- |
| Foto, OCR, konfirmasi, Pekerjaan dan pengesahan | Acceptance browser dan PaddleOCR nyata pada fixture. Artefak per putaran menunjukkan layar dan PDF. |
| Klarifikasi, jawaban kedaluwarsa dan koreksi admin | Tes kontrak dan PostgreSQL `document_flow.test.cjs` mencakup usia pertanyaan, revisi, audit dan bukti pengesahan. |
| Nota sah, stok, batch dan Laporan | Runner mencocokkan snapshot, debit/stok, dan replay dengan PostgreSQL. |
| Pertanyaan traceability dan produksi | OpenClaw adapter memanggil NestJS HTTP dengan sesi owner pada PostgreSQL. Jawaban traceability menampilkan kontribusi sebenarnya dan keterbatasan rework. Pemilih intent eksternal disimulasikan pada uji. |
| Report request, unduhan dan receipt | HTTP, PostgreSQL, file privat lokal, PDF dan XLSX nyata. Provider outbound memakai receipt simulasi. Retry penyimpanan dan pengambilalihan lease kedaluwarsa teruji. |
| Hak akses | Validasi pairing nomor/percakapan, replay kode, admin dan lintas pabrik, serta pencabutan owner diuji. |
| Provider dan deployment | WhatsApp perangkat, OpenRouter berbayar, R2 staging dan production belum diverifikasi dalam putaran ini. |

Audit npm awal menemukan advisory transitif pada `uuid`. Override ExcelJS menggunakan `uuid@11.1.1`, dan audit produksi setelah pembaruan melaporkan nol advisory. [Advisory GitHub](https://github.com/advisories/GHSA-w5hq-g745-h8pq)

Retry notifikasi dibatasi tiga percobaan. Jika provider menerima pesan lalu proses mati sebelum receipt tersimpan, pengiriman ulang pemberitahuan masih mungkin. Kunci artefak persisten mempertahankan satu berkas per format.

Regresi akhir lulus untuk NestJS 77/77, integrasi PostgreSQL 7/7, kontrak REST Langflow stub 1/1, serta FastAPI 16/16. Flutter Analyze bersih dan Flutter Test mencatat 89 lulus dengan 2 fixture eksternal opsional dilewati.

## Ledger

| Task | Status | Evidence | Blocker | Next Action |
| --- | --- | --- | --- | --- |
| Phase 0–1, audit sumber dan katalog | DONE | [Peta data](DOMAIN_DATA_MAP.md), [katalog](METRIC_CATALOG.md) | — | Konfirmasi caller B1 eksternal. |
| Phase 2, Capture/Validation | PARTIAL | Pengujian adapter, PaddleOCR, kontrak revisi/status | Tidak ada pilot atau fixture mitra berizin | Uji reconnect perangkat dan holdout. |
| Phase 3–4, conversational reads | DONE | Tes HTTP owner dan PostgreSQL | — | Validasi pilot reviewer. |
| Phase 5–6, report dan recovery | DONE | Job persisten, dua format, checksum dan outbox dengan receipt sintetis | — | Uji R2 staging dan receipt perangkat. |
| Phase 7, Langflow | DONE | [Evaluasi POC](LANGFLOW_POC_EVALUATION.md) | — | Pertahankan native. |
| Phase 8, acceptance sintetis | DONE | Dua putaran Chrome, OpenClaw, PostgreSQL dan artefak lokal | — | Pertahankan runner di pengujian rilis. |
| Release lintas mesin | UNVERIFIED | Dua salinan identik dari working tree pada satu mesin | Commit acuan tim dan review staging | Jalankan ulang dari dua clone bersih setelah integrasi disetujui. |
