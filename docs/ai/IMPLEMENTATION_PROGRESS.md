# Hasil implementasi SobatNira AI

## Eksekusi lanjutan

Peta endpoint, data resmi, dan definisi metrik tersedia di [peta domain](DOMAIN_DATA_MAP.md) dan [katalog metrik](METRIC_CATALOG.md). Perubahan aditif 019–022 menambah sesi owner, export job, dan outbox notifikasi. OpenClaw dapat menerima pertanyaan produksi dan traceability dari owner yang terhubung, meminta laporan, serta menyampaikan status. NestJS membekukan snapshot, merender PDF/XLSX, memverifikasi artefak, dan melayani unduh bearer. Hak akses diverifikasi lagi saat claim notifikasi. Pengujian detail dan status eksternal ada pada [laporan E2E](E2E_TEST_REPORT.md).

Referensi Implementation Pack yang tetap berlaku adalah OpenClaw sebagai orchestrator, pengambilan angka melalui NestJS, role/pabrik yang diverifikasi di backend, retry persisten yang terbatas, serta POC Langflow terisolasi. Workflow baru mempertahankan Flutter asli tim dan pemisahan antara draf OCR, konfirmasi operator, dan pengesahan admin.

Dua putaran acceptance final lulus dan menghasilkan bukti bisnis yang sama. [Hasil dan batas bukti release](E2E_TEST_REPORT.md#hasil-acceptance-20-november-2026)

Insight produksi menambahkan jawaban gabungan total, grade, dan peringkat sumber nira berdasarkan debit batch yang sudah sah. Peringkat memerlukan basis eksplisit dan ditahan jika data debit belum lengkap. Intent yang dikenali langsung memakai NestJS, dan model opsional hanya menerima kata operasi yang disetujui atau status kelengkapan. Media privat menolak artefak kosong, terlalu besar, atau terpotong. [Bukti acceptance insight produksi](E2E_TEST_REPORT.md#acceptance-insight-produksi)

## Bukti putaran sebelum sesi owner

Basis pengujian `ca91d1b79c0a14b301d1f16a796a43ad86db013e` pada `fix/ai-ocr-evaluation` dengan diff lokal. `origin/main` yang tercatat di clone berada pada `5285171f43e55a64a142840e0fbb610718d0fe22`. Riwayat dan struktur sebelum perubahan ada di [baseline](IMPLEMENTATION_BASELINE.md). Sumber Flutter identik dengan HEAD. Bundel web acuan dari `lib/main.dart` memiliki SHA-256 `F7F5908D26F827FC8E55C4D4E753135EFC7C8BC0F18F2A1D9E04D7A17AF7C382`.

## Keluaran dan peta perubahan

| Prioritas | Status | Perubahan dan bukti |
| --- | --- | --- |
| P0 — kesatuan alur | Runtime sintetis lulus | `apps/api/scripts/local-stack.mjs` menjalankan acceptance pada satu origin dan kini memverifikasi capability, lineage, serta kontribusi bersama pembukuan. Pengujian browser menyelesaikan tiga tugas, satu batch dan unduhan PDF. |
| P0 — angka resmi | Runtime dan tes DB lulus | `production/batches.ts` serta `production/production-report.ts` menampilkan ID dan versi snapshot resmi yang dipakai query Laporan. Rute lama dan kebijakan akses yang masih perlu keputusan tercatat di baseline. |
| P1 — TC-014 | Unit/kontrak lulus | `apps/ai/ocr_parser.py` memakai bukti area sel hasil. `test_ocr.py` menguji kertas kosong, bekas tulisan yang tak terbaca, kolom hilang, referensi aset dan keluaran skema. |
| P1 — TC-016/018 | Tes DB dan smoke lulus | `documents/intake.ts` dan `integrations/openclaw/operator-copy.mjs` mengikat daftar kandidat dan revisi eksplisit pada scope, sambil menjaga quote untuk serah terima. `document_flow.test.cjs` menguji penolakan referensi luar operator/percakapan, konfirmasi revisi lama dan klarifikasi yang kedaluwarsa. |
| P1 — Pengaturan | Dipetakan | Pengaturan master terhubung perlu keputusan harga efektif dan role. Kalkulasi detail batch membekukan nilai input admin pada saat pengesahan. |
| P2 — OCR dan telemetry | Benchmark sintetis dan unit lulus | `benchmark_ocr.py` dan fixture menilai pengelompokan baris serta kebingungan status. `ocr_service.py` mencatat versi prompt dan token jika provider mengirimkannya. `documents/processing.ts` menambahkan ID percobaan, model, dan versi prompt ke log terstruktur. `ci.yml` menjadwalkan tes pada PR dan push main. |
| P3 — capabilities | Runtime lokal dan tes DB lulus | `production/capabilities.ts`, registrasi modul, dan `documents/review.ts` menyediakan empat operasi traceability, lima operasi analytics, serta snapshot baca bagi owner. `batches-database.test.cjs` menguji scope, replay, snapshot dan sumber stok resmi. Lihat [kontrak API](CAPABILITY_API.md). |
| P3 — ekspor dan agen | Sebagian | PDF Flutter berhasil diunduh dan diverifikasi. Worker ekspor backend, file XLSX, distribusi link R2 dan identitas owner melalui WhatsApp mengikuti keputusan di bawah. |
| POC-01 | Runtime lokal teruji, no-go adopsi | `tools/langflow-poc` berisi pembuat flow, runner perbandingan, gateway loopback, custom component, dan uji kontrak. Langflow Base 1.13.3 menyamai jalur native pada 5/5 panggilan. Median 123 ms dibanding 26 ms. [Evaluasi Langflow](LANGFLOW_POC_EVALUATION.md) |

## Bukti uji

| Pemeriksaan | Hasil |
| --- | --- |
| NestJS `npm test` | 77 lulus, 0 gagal, 0 skip. Baseline sempat menerima `503` pada tes token kedaluwarsa, lulus ketika diulang terisolasi dan pada suite akhir. |
| PostgreSQL `batches-database` dan `juice-database` | 6 lulus. Scope owner, admin, lintas pabrik, debit idempoten, serialisasi transfer dan provenance origin teruji. Percobaan transaksi eksplisit perbandingan periode berbenturan dengan savepoint fixture. Implementasi akhir membaca kedua periode dalam satu query dan lulus saat diuji ulang. |
| FastAPI `uv run --locked --extra paddle python -m unittest` | 16 lulus. Gemini memakai respons stub termasuk rate limit dan penggunaan token. |
| Flutter `analyze --no-pub` dan `test --no-pub` | Analisis bersih. 89 lulus, 2 skip karena fixture runtime opsional memerlukan konfigurasi fixture eksternal. |
| Langflow REST contract stub | 1 lulus. Server stub hanya memakai loopback. |
| Browser, API dan database | Dua putaran selesai dengan database awal kosong pada `http://127.0.0.1:8000/`. Login dan pengesahan tiga nota/draf memakai UI tim. Kloter A menerima 90 L nira, konsumsi batch 40 L dan sisa 50 L. Laporan memakai 25 kg gula grade A, Rp500.000 nilai, Rp125.000 biaya, Rp375.000 margin sementara. Replay tidak menggandakan debit. Owner dapat membaca dan menerima `403` saat mencoba mengesahkan batch. Akun luar tidak melihat batch/review pabrik ini. Putaran terakhir juga memeriksa pemisahan akses capability, lineage dua revisi, dan ID snapshot. |
| PDF | Satu halaman per putaran. Isi teks dua PDF terbaru sama dengan dua PDF checkout acuan `ca91d1b`, termasuk kedua kloter, batch, 25 kg gula, dan Rp375.000. |
| Checkout | Bukti A/B dari dua checkout bersih berlaku untuk commit acuan. Diff ini diuji dua kali dari checkout kerja dengan database acceptance berbeda. Verifikasi satu SHA integrasi pada dua checkout bersih masih terbuka. |
| Provider eksternal | WhatsApp memakai adapter simulasi, login memakai stub lokal, media memakai penyimpanan privat lokal, OCR memakai PaddleOCR CPU. WhatsApp perangkat, Supabase, R2, Gemini dan OpenRouter nyata memerlukan verifikasi staging tersendiri. |

### Cakupan kasus PRD

| Kasus | Bukti dan batas |
| --- | --- |
| TC-001–004 | Intake, pemblokiran operator nonaktif, deduplikasi, dan klasifikasi diuji di `document_flow.test.cjs`. Dua jenis nota juga dibaca oleh PaddleOCR saat acceptance. |
| TC-005–008 | Routing ke tinjauan manual dan pengamanan pengesahan tampil dalam acceptance. Foto ulang, angka ambigu dan perlindungan hasil awal saat Gemini berbeda memakai tes kontrak. Untuk nota tak dikenali, alur yang diuji memakai tinjauan manual. Pemilihan jenis oleh operator dan tingkat keberhasilan foto buram di lapangan belum terukur. |
| TC-009–014 | Parser mempertahankan blok/baris, wajan berulang, kg pada ISI, GAMPING sebagai satuan custom, serta status sel hasil. Benchmark Paddle memeriksa dua foto produksi dan tes sintetik terkontrol memeriksa kasus sel kosong. |
| TC-015–018, TC-026 | Acceptance memakai foto lanjutan, deduplikasi dan penolakan konfirmasi revisi lama. Tes PostgreSQL mencakup target ambigu serta serah terima dengan quote, termasuk penolakan referensi tanpa scope dan respons pertanyaan lama. |
| TC-019–021 | Tes PostgreSQL dan kontrak mencakup lease ulang, retry maksimum, antrean manual, respons Gemini `429`, dan fallback OpenRouter. Kegagalan provider disimulasikan. |
| TC-022–025 | `document_flow.test.cjs` dan Flutter test memeriksa antrean yang dibaca dari API, pengesahan pada revisi aktif, audit koreksi, serta dispatch teks terpisah. Pengesahan melalui browser juga dijalankan pada acceptance. |

### Metrik sintetis

- Benchmark PaddleOCR mengklasifikasi 4/4 foto dan membaca 10/10 field berlabel. Jumlah baris per blok kedua nota produksi sesuai (2/2). Median ekstraksi benchmark 25.658,6 ms (4 foto, 3 grup dokumen). P95 belum dilaporkan karena jumlah grup.
- Putaran acceptance pertama mencatat median balasan awal adapter **33,5 ms**, antrean **229,5 ms**, ekstraksi **25.625 ms**. Masing-masing memakai 4 foto dan mengecualikan kiriman duplikat. Script browser menjalankan pengesahan sehingga durasi review fixture belum menggambarkan pekerjaan admin di lapangan.
- Saat putaran kedua berjalan bersamaan dengan pengunduhan dan instalasi paket POC, tiga ekstraksi selesai dalam kisaran 28–74 detik dan satu nota manual memerlukan 176 detik. Browser sempat kehabisan waktu menunggu fixture. Setelah OCR selesai, putaran browser, PDF dan PostgreSQL berhasil. Jalankan pengukuran kinerja dengan beban yang dikendalikan.
- Belum tersedia dua penyebab koreksi terbesar, persentase foto ulang dan koreksi lapangan, tingkat kesalahan kritis yang lolos pengesahan, serta biaya penyedia. Ukur dengan holdout anonim yang dikelompokkan per nota. Hitung perubahan per field dari revisi OCR pertama ke jawaban operator dan revisi sah, gunakan query review timing, lalu bandingkan throughput dan koreksi sebelum/sesudah dengan model yang sama. Gunakan metadata token yang benar-benar tersedia dan tarif provider yang disetujui.

### Status Pengaturan

| Menu | Terhubung |
| --- | --- |
| Identitas pabrik | Form sesi sintetis. Header profil membaca scope pabrik dari sesi login. |
| Fasilitas Produksi | Form sesi sintetis. |
| Pegawai & WhatsApp | Catalog operator API berpabrik. Mutasi mengikuti role pabrik. |
| Shift kerja | Form sesi sintetis. |
| Hak akses & pengguna | Form sesi sintetis. Guard NestJS memverifikasi membership resmi via jalur autentikasi. |
| Aturan produksi | Form sesi sintetis. Batas yang resmi tetap diputuskan backend. |
| Grade produk | Form master sesi sintetis. Nilai grade per batch mengikuti API saat disahkan. |
| Bahan tambahan (BTP) | Form sesi sintetis. |
| Formulir produksi | Form sesi sintetis. Mapping OCR aktif berasal dari schema/parser versi layanan. |
| Harga & Biaya | Master sesi sintetis. Harga grade batch dan biaya kloter eksplisit tersimpan di API dan snapshot. |
| Pemasok | Catalog API berpabrik. |
| Jenis tebu | Catalog API berpabrik. |
| Keluar | Mengakhiri sesi klien. |

## Reproduksi dan urutan lanjut

Ikuti [panduan setup dan fixture](README.md). Buat database sintetis kosong, bangun Flutter dari `lib/main.dart`, jalankan `npm.cmd run local:stack -- --web --acceptance` dari `apps/api` dan buka `http://127.0.0.1:8000/`. Untuk benchmark, dari `apps/ai` jalankan `uv run --locked --extra paddle python benchmark_ocr.py fixtures/acceptance/ground-truth.json --split test`.

1. Setujui cakupan role dan aturan efektif master harga/biaya serta inventaris pemakai rute B1. [Register keputusan](DECISIONS_REQUIRED.md)
2. Verifikasi worker PDF/XLSX pada bucket R2 privat staging dan sahkan retensi serta akses unduh dari UI tim.
3. Ulangi skenario yang sama dari dua checkout bersih setelah tersedia satu SHA integrasi yang disetujui. Jalankan pilot WhatsApp perangkat terpisah dan ukur pengiriman serta koreksi dengan data berizin.
4. Bandingkan selective reread dan baseline Paddle pada holdout yang sama sebelum mengunci model.
