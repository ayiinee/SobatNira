# Intake dan review dokumen AI

Skema bersama ada di [schemas](schemas/) dan contoh sintetis ada di [examples](examples/). Periksa [audit awal](IMPLEMENTATION_AUDIT.md) dan [log implementasi](IMPLEMENTATION_LOG.md) untuk status tiap tahap. Tim dapat meminta PRD dan register keputusan AI yang lengkap melalui kanal privat, lalu menyimpannya di `docs/internal/ai/`.

## Menjalankan lokal

1. Siapkan PostgreSQL kosong untuk pengembangan, atur `DATABASE_URL` untuk NestJS, lalu jalankan `npm run db:migrate` dari `apps/api`. Gunakan principal database backend yang memiliki tabel workflow. Row-level security aktif pada tabel workflow dan akses dari aplikasi selalu melalui NestJS. Daftarkan kontak aktif melalui `operator_contacts` dan anggota pabrik `ADMIN` atau `OWNER` melalui `review_memberships`. Gunakan UUID `user_id` dari akun Supabase untuk keanggotaan tersebut.
2. Atur `WHATSAPP_ADAPTER_INTERNAL_TOKEN` pada backend dan OpenClaw, serta `AI_SERVICE_INTERNAL_TOKEN` pada backend dan FastAPI. Tentukan `DOCUMENT_MEDIA_DIR` di folder privat untuk pengembangan lokal, atau isi `R2_ENDPOINT`, `R2_BUCKET`, `R2_ACCESS_KEY_ID`, dan `R2_SECRET_ACCESS_KEY` untuk bucket privat. Atur `SUPABASE_URL` dan `SUPABASE_ANON_KEY` di backend. Aktifkan `DOCUMENT_WORKER_ENABLED=true` dan jalankan `npm run dev`. `AI_SERVICE_BASE_URL` memakai `http://127.0.0.1:8000` secara default. `API_HOST` memakai `127.0.0.1` secara default.
3. Dari `apps/ai`, jalankan `uv sync --locked --extra paddle --python 3.13` pada Windows/Linux x64 dan `uv run --locked --extra paddle uvicorn main:app --host 127.0.0.1 --port 8000`. PaddleOCR menyiapkan model pada pemanggilan pertama. Tetapkan `PADDLE_PDX_CACHE_HOME` jika lokasi cache perlu dipindah. `OCR_MEDIA_BASE_URL` memakai `http://127.0.0.1:3000` secara default. Untuk penggunaan visual yang sudah disetujui, isi `GEMINI_API_KEY` dan `GEMINI_VISION_MODEL` pada FastAPI agar hanya crop ambigu yang dapat dibaca ulang.
4. Jalankan Flutter dari `apps/mobile` dengan `--dart-define=SUPABASE_URL=...` dan `--dart-define=SUPABASE_ANON_KEY=...` berisi URL dan key publik proyek. Gunakan `--dart-define=API_BASE_URL=...` jika alamat backend berbeda. Setelah onboarding demo, buka **Pekerjaan** dan masuk dengan akun yang telah terdaftar pada pabrik. Sesi review terpisah dari onboarding dan disimpan di memori aplikasi. Atur `MOBILE_WEB_ORIGINS` pada backend jika Flutter web menggunakan origin selain pengembangan lokal.

## OpenClaw

Gunakan akun WhatsApp khusus yang terhubung melalui OpenClaw/Baileys. Muat plugin lokal `apps/api/integrations/openclaw`, isi `accountId` dan `mediaDir` dengan akun khusus dan direktori staging media OpenClaw, lalu atur `SOBATNIRA_API_URL` dan token adapter pada proses gateway. Plugin memakai hook `inbound_claim` dan memproses DM dari akun yang dikonfigurasi. Lihat [hooks pesan OpenClaw](https://docs.openclaw.ai/plugins/hooks/messages) dan [cara menyiapkan akun WhatsApp](https://docs.openclaw.ai/channels/whatsapp).

Bot memberi tanda terima dan menyediakan `STATUS <dokumen> <revisi>` untuk membuka draf. Jika gateway mendukung penyiapan notice sesi dan sesi masih aktif, plugin juga mencoba mengirim ringkasan setelah ekstraksi. Ringkasan menyertakan perintah `KOREKSI` dan `KONFIRMASI` dengan ID revisi. Untuk foto nota produksi lanjutan, balas kiriman foto yang dikenal atau gunakan caption `REVISI <dokumen>`. Gunakan `BARU` untuk menyatakan nota baru ketika terdapat kandidat lain. Draf yang rujukannya meragukan tersimpan sebagai bukti dan menunggu pilihan eksplisit.

Untuk mengaktifkan bantuan bahasa natural pada balasan ke foto yang dikenali, isi `OPENROUTER_API_KEY`, `OPENROUTER_AGENT_MODEL`, dan `OPENROUTER_ALLOWED_PROVIDERS` (slug provider yang disetujui, dipisahkan koma) pada gateway. `OPENROUTER_AGENT_FALLBACK_MODEL` opsional untuk gangguan model atau jaringan. Pilih ID model tertentu yang mendukung function calling dan endpoint zero data retention. Plugin mengirim maksimal 300 karakter pertanyaan setelah menyamarkan pola ID, email, dan nomor, tanpa foto, draf, atau riwayat. Hasil model memilih jenis panduan baca-saja. Konfirmasi dan koreksi tetap memakai perintah revisi eksplisit. Jika OpenRouter gagal atau konfigurasi belum lengkap, plugin tetap memakai template. [Kontrak tool calling OpenRouter](https://openrouter.ai/docs/features/tool-calling)

## Notifikasi Pekerjaan

Jalankan `npm run db:migrate` untuk memasang migration `002`. Setelah konfirmasi operator, admin aktif di pabrik terkait menerima badge laporan baru di Pekerjaan. Flutter memeriksa badge saat membuka tab dan setiap 30 detik selama tab aktif. Membuka detail menandai notifikasi itu sudah dibaca untuk admin tersebut. Owner tetap memiliki akses review. Notifikasi berlaku untuk laporan yang dikonfirmasi setelah migration ini dan tersedia ketika aplikasi terbuka.

## Benchmark OCR lokal

Dari `apps/ai`, jalankan `uv run --locked --extra paddle python benchmark_ocr.py <manifest.json>`. Simpan manifest dan foto anonim berlabel pada direktori privat yang sama. Setiap foto membutuhkan tipe dokumen yang diharapkan dan dapat memiliki anotasi berdasarkan path field, termasuk raw value, normalized value, status, atau unit.

```json
[
  {
    "image": "nota-sintetis.png",
    "document_type": "TRUCK_ARRIVAL_NOTE",
    "fields": { "header.net_weight_kg": { "normalized_value": 1250, "unit": "kg" } }
  }
]
```

Hasil mencakup jumlah gambar, matriks klasifikasi, hitungan benar/salah/tidak ditemukan per field, dan median waktu pemrosesan. Benchmark memanggil PaddleOCR lokal tanpa mengirim foto ke Gemini.

## Menjalankan tes

- `apps/api` dengan PostgreSQL pengujian dan `TEST_DATABASE_URL` menjalankan `npm test`, termasuk migrasi dan alur lintas endpoint dengan respons OCR serta autentikasi sintetis. Tes memakai schema yang dibuat khusus dan menghapus schema itu setelah selesai.
- `apps/ai` menjalankan `uv run --locked python -m unittest`. Tes parser memakai hasil pengenalan sintetis untuk dua nota dan mencakup kode gagal, unit, evidence, serta perbedaan kandidat visual.
- `apps/mobile` menjalankan `flutter analyze` dan `flutter test`. Tes Pekerjaan menjalankan navigasi normal dan payload validasi terhadap mock HTTP.
