# Baseline implementasi paket AI

## Baseline setelah acceptance kelima capability

`fix/ai-ocr-evaluation` masih berbasis `ca91d1b79c0a14b301d1f16a796a43ad86db013e` dengan perubahan lokal. Bukti terbaru adalah dua acceptance sintetis, migrasi aditif 019–022, dan pengujian owner serta ekspor persisten yang tercatat di [laporan E2E](E2E_TEST_REPORT.md). Audit tambahan masih relevan untuk rework, mapping label, dan penyedia eksternal. Fitur percakapan owner, PDF/XLSX dan notifikasi simulasi sudah melampaui baseline audit tambahan.

Gap teknis berikutnya adalah pertanyaan gabungan produksi, grade, dan peringkat kontribusi. POC sebelumnya memakai kloter yang ditentukan di awal. Jawaban owner saat ini memilih satu tampilan per pertanyaan, dan pemilih model dapat mengganti maksud yang sudah jelas. Peringkat yang menyangkut kebijakan bisnis tetap terbuka. Implementasi berikutnya menerima basis yang disebut eksplisit untuk satu pembacaan ledger dan mempertahankan permintaan klarifikasi saat basis ambigu.

## Baseline eksekusi lanjutan

Pada 20 November 2026, branch `fix/ai-ocr-evaluation` tetap di `ca91d1b79c0a14b301d1f16a796a43ad86db013e` dengan perubahan lokal dari fase sebelumnya. Runtime sintetis Capture/Validation, PostgreSQL, PDF Flutter, capability baca owner, dan POC Langflow REST sudah memiliki bukti pada putaran terdahulu. Runner browser sedang diverifikasi setelah putaran pertama terhenti ketika Flutter build dan OCR berjalan bersamaan. Tabel/data resmi dipetakan di [peta domain](DOMAIN_DATA_MAP.md).

OpenClaw menangani intake/konfirmasi dan intent bantuan operator. Plugin belum mengirim pertanyaan owner ke capability NestJS. Ekspor PDF yang berjalan ada di Flutter. Worker report/Excel serta binding owner WhatsApp belum aktif. Rework yang ditemukan berada di jalur B1 lama; belum ada kaitan ID resmi ke batch PostgreSQL yang digunakan Flutter. Baseline 38,4 detik dari audit tambahan dan hasil 25,7 detik pada benchmark lokal sebelumnya mengukur putaran terpisah. Keduanya memakai sampel kecil dengan hasil klasifikasi 4/4 dan field berlabel 10/10. Lingkungan terhubung memakai template konfigurasi; akses WhatsApp perangkat, provider berbayar, R2 privat staging dan production berada di luar verifikasi.

Checkout awal `fix/ai-ocr-evaluation` pada `ca91d1b79c0a14b301d1f16a796a43ad86db013e` bersih. SHA ini sama dengan audit yang dilampirkan. `main` lokal berada pada `5285171f43e55a64a142840e0fbb610718d0fe22`. Sumber paket dibaca dari ZIP pengguna yang diekstrak ke `.tmp/ai-implementation-pack/` dan dipadankan dengan `docs/internal/ai/`, `docs/internal/knowledge-pack/`, serta `docs/ai/schemas/` dan `docs/ai/examples/` pada checkout.

## Arsitektur dan bukti

- Flutter tim masuk melalui `apps/mobile/lib/main.dart` dan memakai API NestJS melalui konfigurasi satu origin. Tidak ada entry point Flutter baru dalam pekerjaan ini.
- OpenClaw/Baileys mengirim event ke adapter `apps/api/integrations/openclaw`. NestJS mengendalikan otorisasi, media privat, transaksi, revisi, pekerjaan OCR dan notifikasi persisten di PostgreSQL. FastAPI menjalankan PaddleOCR dan selective Gemini reread bila dikonfigurasi. OpenRouter dipakai untuk bantuan intent chat.
- Lockfile aktif adalah `apps/api/package-lock.json`, `apps/ai/uv.lock` dan `apps/mobile/pubspec.lock`. Contoh konfigurasi ada di `.env.example`, `.env.connected.example` dan `apps/api/.env.example`. Migrasi produksi dan OCR berada di `apps/api/migrations/` dan `apps/api/migrations/ocr/`.
- Baseline lokal terbaru adalah FastAPI 15 lulus, Flutter Analyze bersih dan Flutter 89 lulus dengan 2 fixture opsional terlewati. NestJS dengan PostgreSQL sintetis mencatat 76 lulus dan 1 gagal pada putaran paralel awal. Tes token tidak valid menerima `503` dan mengharapkan `401`. Verifikasi terisolasi dicatat pada laporan eksekusi.
- Bukti historis untuk SHA ini mencakup dua checkout dengan adapter WhatsApp simulasi, PaddleOCR CPU, PostgreSQL, Flutter Chrome, dan PDF. Baseline benchmark sintetis memiliki 4/4 klasifikasi dan 10/10 field berlabel. Timing dan bukti runtime terbaru dicatat terpisah. Supabase, R2, provider eksternal, dan WhatsApp live berada di luar verifikasi lokal ini.

## Rekonsiliasi jalur data

| Jalur | Caller dan layanan | Sumber resmi atau batas | Akses dan tes |
| --- | --- | --- | --- |
| `/tenants/:tenantId/factories/:factoryId/lots`, `/juice/availability` | Flutter Kloter, `LotsRepository`, `JuiceRepository` | Penerimaan/penggilingan yang disahkan, rekonsiliasi, ledger dan reservasi nira | Admin/owner berpabrik. `production-database`, `juice-database` |
| `…/production/batches`, `…/production/lots/:id/costs` | Flutter Detail Batch, `Batches` | `production_batches`, `batch_grade_results`, `lot_production_costs`, reservasi nira, kalkulasi persis pada saat pengesahan | Baca admin/owner, perubahan batch dan biaya admin. `batches-database` |
| `…/production/production-report`, `/recap`, `/profit-report` | Flutter Laporan, Rekap dan PDF, `Batches` | Snapshot kumulatif terakhir per kloter pada `production_calculation_snapshots`. Periode mengikuti penerimaan kloter. Laporan produksi juga memuat penerimaan tanpa hasil | Admin/owner saat baseline. `production-report`, `batches-database` dan acceptance browser |
| `/batches`, `/stock/sugar`, `/batches/:id/economics` | `BatchesModule`, `EconomicsModule`, tes B1, adapter konfigurasi lama | Model, kalkulasi, penyimpanan dan ledger B1 terpisah. Konsumen eksternal belum terinventarisasi | Scope pada guard dan policy layanan lama. `b1-batches` |
| `/dashboard/production`, `/analytics/production`, `/exports/batches.csv` | `ReportingModule`, `ReportingService`, tes B1 | Agregat B1 dari `BatchesService`, bukan snapshot produksi Flutter. CSV lama. PDF Flutter dibentuk di klien. Belum ditemukan ekspor XLSX resmi | Guard awal admin/owner dengan pembatasan tambahan di layanan B1. `b1-batches` |
| `/production-masters/prices`, `/production-masters/configs` | `ProductionMastersModule`, tes B1. Flutter Pengaturan harga/biaya memakai sesi demo | Penyimpanan master B1 terpisah. Harga batch dan biaya kloter resmi disimpan melalui jalur `…/production` | CRUD awal B1 dan biaya kloter telah teruji. Pemakaian harga efektif pada UI terhubung memerlukan keputusan |

Tool baru diarahkan ke jalur resmi berpabrik. Jalur B1 tidak dimigrasikan atau dihapus pada basis bukti caller yang tersedia. Konflik visibilitas laporan Flutter lama terhadap kebijakan owner khusus dicatat di register keputusan.

## Gap dan urutan implementasi

1. Pertahankan alur rilis tunggal dan ukur ulang dengan fixture sintetis.
2. Perbaiki `TC-014` bila area sel dapat dibuktikan kosong, dan `TC-016/018` pada scope operator, percakapan, dokumen, revisi dan pertanyaan.
3. Tambahkan pengukuran sintetis dan CI otomatis. Pengambilan model/provider di CI memerlukan job terpisah.
4. Tambahkan tool baca melalui guard NestJS dengan sumber snapshot dan provenance resmi. Aktivasi kanal owner melalui WhatsApp dan worker ekspor menunggu keputusan terkait.
5. Evaluasi POC Langflow terisolasi. Runtime Docker/Langflow belum ditemukan di mesin baseline.
