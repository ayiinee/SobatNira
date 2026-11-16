# Nota hasil produksi: penggilingan dan nira per kloter

Modul ini memproses bagian penggilingan dari **nota hasil produksi gabungan**, yaitu nota kedua setelah nota truk masuk. Satu nota kedua dapat memuat total nira, pembagian batch, pemasakan, penimbangan, dan grade. API tidak mensyaratkan nota fisik penggilingan terpisah. Untuk pengembangan sebelum OCR tersedia, sumbernya masih fixture sintetis.

Dalam tahap ini, nota hasil merepresentasikan penggilingan selesai untuk satu kloter. Saat admin mengesahkan, backend mengambil seluruh berat tebu dari penerimaan sah, mengurangi stok tebu sebesar berat tersebut, lalu mencatat total nira yang dilaporkan. Berat tebu tidak dihitung dari liter nira dan tidak diterima dari input klien.

## Batas implementasi

- NestJS menangani validasi, akses, revisi, audit, dan ledger resmi penggilingan. FastAPI/OCR belum dipanggil oleh modul ini.
- Baris `reportedBatches` adalah rincian batch yang dilaporkan pada nota dan disahkan sebagai snapshot bersama penggilingan. `batchReference` merupakan label dari nota, belum identitas batch pemasakan resmi. `reportedBatchCount` menghitung baris unik yang dilaporkan, bukan perkiraan `total / 115`.
- Kontribusi nira kloter asal pada batch campuran dapat dicatat tanpa menghitung seluruh volume batch sebagai milik kloter ini. Rekonsiliasi label batch lintas nota, transfer stok, ledger pemasakan, hasil timbang, dan grade resmi perlu modul lanjutan setelah contoh nota tersedia.
- `stock/juice` saat ini menunjukkan saldo ledger tahap penggilingan (nira dihasilkan). Rincian batch belum mendebit ledger tersebut; jangan mengartikannya sebagai nira tersisa setelah pemasakan. Proses lanjutan harus membukukan pemakaian, sehingga nira tidak dipakai dua kali.
- Upload bukti R2 masih terpasang pada nota penerimaan. Bukti nota kedua dan kontrak lengkap OCR akan mengikuti struktur nota sebenarnya; jangan mengirim nota asli ke Git.

## Setup dan pemeriksaan

Jalankan dari `apps/api` dengan `.env` development yang sudah terisi:

```sh
npm ci
npm run db:migrate
npm test
npm run test:milling-db
npm run dev
```

Migrasi `006_milling_documents.sql` menambah dokumen, revisi, pergerakan tebu keluar, dan ledger nira. Migrasi `007_whole_lot_milling.sql` mengikat berat yang diproses ke penerimaan sah, membatasi satu pembukuan penggilingan per kloter, dan menambahkan snapshot rincian batch. Migrasi yang sudah diterapkan tidak diedit ulang.

Tes database memakai fixture tenant/pabrik/pengguna sintetis tanpa onboarding atau pengiriman email. Tes dasar di-rollback; tes konkurensi memakai fixture sementara yang di-commit dan dihapus berdasarkan UUID yang dibuat tes. Jalankan pada database development.

## Endpoint

Semua endpoint memerlukan Bearer Supabase dan membership aktif `admin` atau `owner` pada tenant/pabrik di path. Prefix contoh:

```text
/tenants/{tenantId}/factories/{factoryId}
```

| Method | Path sesudah prefix | Kegunaan |
| --- | --- | --- |
| POST | `/production-result-documents/synthetic` | Draf sintetis bagian penggilingan nota hasil gabungan |
| GET | `/production-result-documents` | Daftar; filter `status`, `lotId`, `limit`, `offset` |
| GET | `/production-result-documents/{id}` | Draf aktif, sumber asli, revisi, dan hasil pengesahan |
| PATCH | `/production-result-documents/{id}/draft` | Koreksi dengan alasan dan `expectedRevision` |
| POST | `/production-result-documents/{id}/confirm-synthetic` | Simulasi konfirmasi operator menuju antrean admin |
| POST | `/production-result-documents/{id}/approve` | Pengesahan dan pembukuan atomik |
| GET | `/production-result-documents/{id}/revisions` | Riwayat ekstraksi dan koreksi |
| GET | `/production-result-documents/{id}/history` | Audit perubahan status dan data |
| GET | `/lots/{lotId}/milling-summary?synthetic=true` | Hasil penggilingan sah dan rincian/jumlah batch per kloter |
| GET | `/stock/sugarcane?synthetic=true&lotId={lotId}` | Saldo tebu setelah penerimaan/penggilingan |
| GET | `/stock/juice?synthetic=true&lotId={lotId}` | Saldo ledger nira hasil penggilingan |

Daftar, history, dan revisions memakai pagination yang sama dengan dokumen penerimaan. `synthetic` bawaan `false` pada saldo/summary agar demo tidak masuk angka riil. Summary mengembalikan `milling: null` jika kloter belum memiliki penggilingan sah pada kategori tersebut; kloter di luar scope menghasilkan 404.

## Contoh alur sintetis

1. Buat dan sahkan [penerimaan tebu](backend-intake-documents.md) untuk kloter yang sama. Nota hasil boleh dibuat sebelum penerimaan sah, tetapi pengesahannya tertahan 409 sampai prasyarat tersedia.
2. `POST /production-result-documents/synthetic`:

```json
{
  "lotId": "40000000-0000-4000-8000-000000000001",
  "requestId": "50000000-0000-4000-8000-000000000001"
}
```

Simpan dan gunakan kembali `requestId` yang sama untuk retry sumber yang sama. Fixture melaporkan 250 L dan dua batch masing-masing 115 L. Nilai ini ilustrasi; tidak berasal dari rumus konversi berat tebu. Mengulang request mengembalikan dokumen yang sama, sedangkan memakai key yang sama untuk kloter berbeda menghasilkan 409.

3. Koreksi draf jika perlu, `PATCH /production-result-documents/{id}/draft`:

```json
{
  "expectedRevision": 1,
  "reason": "Periksa pembagian nira pada contoh sintetis",
  "changes": {
    "occurredAt": "2026-11-16T09:00:00+07:00",
    "juiceProducedLiters": "250",
    "reportedBatches": [
      { "batchReference": "CONTOH-1", "wokNumber": 1, "totalJuiceLiters": "115", "sourceJuiceLiters": "115" },
      { "batchReference": "CONTOH-2", "wokNumber": 2, "totalJuiceLiters": "115", "sourceJuiceLiters": "115" },
      { "batchReference": "CONTOH-CAMPURAN", "wokNumber": 3, "totalJuiceLiters": "100", "sourceJuiceLiters": "20" }
    ]
  }
}
```

Baris campuran menyatakan 20 L dari kloter ini pada batch total 100 L. Sumber 80 L lainnya harus direkonsiliasi pada modul batch lanjutan. Sisa nira tidak menghasilkan batch otomatis. Jika rincian belum terambil, simpan `reportedBatches: null`; sebelum konfirmasi, lengkapi dari nota. Daftar kosong berarti tidak ada baris batch yang dilaporkan.

4. `POST /production-result-documents/{id}/confirm-synthetic`, kemudian `POST /production-result-documents/{id}/approve`. Keduanya memakai revisi aktif:

```json
{ "expectedRevision": 2 }
```

Konfirmasi mengantrekan dokumen untuk admin. Pengesahan membukukan berat tebu penerimaan sebagai `milling.caneConsumedKg`, total nira sebagai `milling.juiceProducedLiters`, dan baris/jumlah batch sebagai `milling.reportedBatches`/`reportedBatchCount`. Membuat atau mengirim draf belum mengubah stok. Jalur OCR/WhatsApp nantinya memasukkan draf nota gabungan ke lifecycle ini; pengesahan admin tetap diperlukan sesuai lingkup fitur saat ini.

## Validasi dan konsistensi

- Satuan eksplisit: tebu kg, nira L. Angka JSON harus berupa string desimal, tanpa eksponen/pemisah ribuan, maksimal 64 karakter. Perhitungan mempertahankan presisi dengan PostgreSQL `numeric` atau integer berskala, tanpa floating-point/pembulatan bisnis.
- Waktu ISO wajib berzona dan tidak boleh mendahului penerimaan. Waktu kejadian, konfirmasi, dan pengesahan disimpan terpisah.
- Tiga wajan (`wokNumber` 1–3) boleh dipakai berulang untuk jumlah batch yang lebih banyak. Kapasitas awal per baris 115 L. Modul tidak menetapkan batas tiga batch total atau memesan jadwal wajan; waktu pemasakan aktual mengikuti modul berikutnya.
- Setiap kontribusi sumber positif, tidak melebihi total batch, dan seluruh kontribusi kloter pada nota tidak boleh melebihi hasil niranya. Total nira nol hanya dapat disahkan dengan daftar batch kosong. Minimum isi normal tidak dipakai untuk mengarang batch atau transfer otomatis.
- `expectedRevision` menahan edit/pengesahan dari layar lama. Revisi koreksi admin tetap menyimpan referensi revisi konfirmasi operator. Sumber sintetis asli tidak ditimpa.
- Pengesahan mengunci dokumen dan kloter, membaca ulang penerimaan serta saldo pada snapshot baru, memastikan saldo tebu sama dengan penerimaan, kemudian menulis record, stok tebu negatif, stok nira, status, dan audit dalam satu transaksi. Kegagalan salah satu membatalkan semuanya.
- Retry pengesahan revisi yang sama mengembalikan hasil yang sama. Dua dokumen berbeda untuk kloter sama bersaing: hanya satu yang boleh membukukan stok. Constraint database mengikat debit kg dan kredit L ke record sumbernya.
- Dokumen sah tidak dapat diedit dengan PATCH draf. Koreksi resmi berikut rekonsiliasi tahap turunannya memerlukan alur tersendiri.
- Endpoint sintetis dan simulasi konfirmasi dinonaktifkan pada `APP_ENV=production`. Tidak ada hak baca langsung tabel untuk `anon` atau `authenticated`; NestJS membatasi semua operasi dengan tenant/pabrik dan membership terbaru.

## Meninjau perubahan Git

Branch implementasi: `codex/feat/api-milling-flow`. Gunakan `git log --oneline` untuk melihat commit kontrak/skema, alur API, dan pengujian/dokumentasi secara terpisah. Contoh pemeriksaan satu bagian:

```sh
git show c4ee50c
git diff origin/main...HEAD -- apps/api docs
```

Branch belum dipush otomatis. Kredensial dan acuan internal tetap diabaikan Git.
