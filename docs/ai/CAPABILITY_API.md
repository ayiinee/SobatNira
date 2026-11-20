# Capability API untuk owner

`POST /tenants/{tenantId}/factories/{factoryId}/capabilities/query` memakai token sesi yang sama dengan aplikasi. NestJS memverifikasi keanggotaan aktif dan role owner pada pabrik dalam URL. Untuk lineage nota, akses review owner juga harus aktif. Gunakan sesi sintetis dari prosedur lokal di [README](README.md) untuk pengujian.

```json
{
  "operation": "get_production_summary",
  "arguments": {
    "from": "2026-11-16T00:00:00+07:00",
    "before": "2026-11-17T00:00:00+07:00"
  },
  "correlation_id": "11111111-1111-4111-8111-111111111111"
}
```

`request_id` dan `correlation_id` opsional dan harus UUID. Panggilan membaca data tanpa efek samping. Body menerima operasi dari daftar dan field argumen di bawah. Token dan membership menentukan hak akses. Identitas, role, SQL, dan rumus dari body ditolak.

| Operasi | Argumen | Sumber dan keluaran |
| --- | --- | --- |
| `get_lot_traceability` | `lotId`, `synthetic?` | Referensi penerimaan dan penggilingan sah. Relasi kosong disebutkan secara eksplisit. |
| `get_batch_traceability` | `batchId` | Batch sah, wajan, grade, dan reservasi nira yang dikonsumsi. |
| `get_document_lineage` | `documentId`, `beforeVersion?` | Riwayat revisi, referensi submission/media, status job, waktu konfirmasi dan pengesahan. Paginasi dengan `nextBeforeVersion`. Metadata ini tidak berisi foto, URL bertanda tangan, prompt, nilai OCR mentah, atau nomor operator. |
| `get_material_contributions` | Salah satu `batchId` atau `lotId`. `synthetic?` untuk kloter, `offset?` berupa string | Debit yang sudah di-booking ke inventaris melalui batch sah. ID asal dan lokasi stok disajikan terpisah dalam mL. |
| `get_lot_contribution_summary` | `lotId`, `synthetic?`, `offset?` berupa string | Detail kontribusi dan `pageConsumedQuantityMl`. Jumlah berlaku untuk halaman yang dikembalikan. |
| `get_production_summary` | `from`, `before`, `synthetic?` | Angka agregat query Laporan Flutter dan sumber snapshot kloter yang sama. |
| `get_grade_distribution` | `from`, `before`, `synthetic?` | Berat dan nilai produksi per grade dari batch sah. |
| `get_production_metrics` | `from`, `before`, `synthetic?` | Total produksi dan metrik yang dibekukan dalam snapshot tiap kloter. |
| `compare_production_periods` | `first: {from, before}`, `second: {from, before}`, `synthetic?` | Total resmi untuk dua periode dari satu snapshot pembacaan PostgreSQL. |
| `get_production_insight` | `from`, `before`, `synthetic?`, `contributionBasis?` | Total dan grade pada pembacaan resmi yang sama. Dengan basis eksplisit `consumed_nira_by_lot_received_at`, sertakan kloter asal dengan debit nira terbesar. |
| `get_report_snapshot` | `from`, `before`, `synthetic?` | Bagian baca untuk laporan dan narasi. Mengembalikan data sumber terkini secara konsisten dalam satu query, mencantumkan ID kalkulasi yang sudah tersimpan. |

Periode harus berupa timestamp ISO 8601 dengan zona waktu. Periode inklusif pada `from` dan eksklusif pada `before`, berdasarkan penerimaan kloter. Tiap pembacaan laporan maksimal 366 hari dan 500 kloter. Persempit rentang jika batas terlampaui. `synthetic` adalah boolean opsional dengan nilai awal `false`. Kontribusi dibatasi 100 baris per halaman.

Respons memuat `scope`, `request_id`, `correlation_id`, `status`, `data_status`, `missing_relations`, `limitations`, `sources`, `result`, dan `generated_at`. Gunakan string desimal sebagaimana dikembalikan server. Harga, biaya, dan margin mencerminkan cakupan kalkulasi produksi yang berlaku. Operasi ini belum membuat permintaan ekspor atau membekukan hasil pembacaan menjadi dokumen ekspor. Status HTTP `403` berarti hak akses tidak memenuhi kontrak. Status `404` berarti resource tidak tersedia dalam scope yang diizinkan.

## Sesi owner dan ekspor

Jalur owner WhatsApp dan worker ekspor memakai opt-in `OWNER_AGENT_ENABLED=true` dan `REPORT_EXPORT_ENABLED=true`. Mulai dari environment sintetis. Terapkan migrasi aditif 019–022. OpenClaw dan NestJS harus memakai nilai flag dan token adapter yang sama. Jalur utama Flutter tetap memakai widget tim.

1. Dengan Bearer owner, panggil `POST /tenants/{tenantId}/factories/{factoryId}/owner-agent/sessions` dan kirim `{"phone":"+12025550105"}` menggunakan nomor fixture. Balas di percakapan langsung dengan `SAMBUNG <kode>`. Kode sekali pakai berlaku 10 menit. Sesi yang ditautkan berlaku satu jam dan mengikuti role serta membership terkini.
2. Tanyakan `ASISTEN produksi kemarin`, `ASISTEN distribusi grade minggu ini`, `ASISTEN rendemen bulan lalu`, `ASISTEN bandingkan bulan ini dan bulan lalu`, atau `ASISTEN telusuri batch <UUID>`. Periode relatif memakai WIB, awal minggu Senin, dan waktu event provider. Periode tanggal eksplisit memakai `YYYY-MM-DD`. Relasi material memakai UUID resmi.
3. Gunakan `ASISTEN buat laporan 2026-11-16` dan `ASISTEN status laporan <UUID>`. Gunakan `PUTUS` untuk mencabut sesi. Notifikasi dikirim setelah worker membaca ulang kedua file dan memverifikasi hasilnya. Agent tidak menerima token owner atau file.

Pertanyaan “berapa total produksi minggu ini, bagaimana distribusi grade-nya, dan kloter mana yang memberikan kontribusi terbesar?” mengembalikan total dan grade lalu meminta basis peringkat. Untuk meminta ukuran spesifik, gunakan `ASISTEN total produksi, distribusi grade, dan kontribusi nira terbesar minggu ini berdasarkan tanggal penerimaan kloter batch`. Peringkat mengelompokkan debit nira batch sah menurut UUID kloter asal dan menyajikan nilai seri. Jika debit sebuah batch berbeda dari volume yang disahkan, hasil menandai cakupan parsial dan menahan peringkat. Untuk permintaan `jelaskan`, model hanya dapat memilih fokus dari status cakupan setelah pemeriksaan akses. Angka, identitas pabrik dan referensi tidak dikirim ke model.

API ekspor memakai awalan `/tenants/{tenantId}/factories/{factoryId}/report-exports`.

| Permintaan | Kontrak |
| --- | --- |
| `POST /` | Bearer owner dan header `Idempotency-Key: <UUID>`. Body `{from,before,synthetic?}`. Mengembalikan `202` dengan status. Kunci dan input yang sama mengembalikan ID yang sama. Input lain dengan kunci yang sama ditolak. |
| `GET /{id}` | Status `QUEUED`, `PROCESSING`, `READY`, atau `FAILED`. Format unduhan diumumkan saat `READY`. |
| `GET /{id}/snapshot` | Snapshot yang dibekukan saat meminta ekspor, termasuk ID perhitungan resmi dan periode. |
| `GET /{id}/files/pdf`, `GET /{id}/files/xlsx` | Bearer pemohon yang masih owner pada pabrik tersebut. Server memeriksa checksum artefak. `409` selama file belum siap, `404` di luar permintaan yang berwenang. |

PDF server dan XLSX menggunakan snapshot sama, termasuk tabel ringkasan, grade, dan kloter. XLSX menyimpan nilai desimal sebagai teks agar presisi tetap utuh. PDF server memakai font standar dan mengganti karakter di luar cakupannya dengan `?`. PDF dari Flutter tetap tersedia melalui alur yang sudah ada. R2 untuk staging membutuhkan verifikasi bucket privat dan izin terpisah sebelum uji pengiriman nyata. [pdf-lib](https://pdf-lib.js.org/docs/api/classes/pdfdocument) · [ExcelJS](https://github.com/exceljs/exceljs)
