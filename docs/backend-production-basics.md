# Data dasar pemasok dan kloter

Modul ini menyediakan metadata pemasok dan identitas dasar kloter sebelum alur dokumen, stok dan produksi resmi dihubungkan. Onboarding akun dapat dikerjakan kemudian; pengujian modul menggunakan identitas dan data sintetis.

## Cakupan

- Pemasok berada pada tingkat tenant dan dapat dipakai oleh beberapa pabrik dalam tenant tersebut.
- Kloter berada pada satu tenant/pabrik dan merujuk pemasok dalam tenant yang sama.
- Admin dan owner dengan membership aktif dapat mengelola metadata dalam cakupannya.
- Setiap pembuatan/perubahan dicatat bersama actor, waktu dan snapshot sebelum/sesudah dalam satu statement database yang atomik.
- Pemasok dapat dinonaktifkan. Pemasok nonaktif tidak dapat dipilih untuk kloter baru; kloter lama tetap dapat dibaca.
- Tidak ada endpoint penghapusan fisik pemasok atau kloter.

Kloter menggunakan UUID internal. `displayCode` bersifat opsional dan diisi manual; sistem belum menghasilkan format/suffix resmi atau memakai kode untuk pencocokan otomatis. Dua kiriman dengan kode tampilan yang sama tetap memiliki UUID berbeda. Nama pemasok juga tidak dijadikan identitas unik.

Endpoint metadata dasar tidak mencatat berat, Brix atau pengesahan. Gunakan [modul dokumen penerimaan](backend-intake-documents.md) untuk mengesahkan draf penerimaan dan membukukan stok tebu masuk. Pemakaian material, batch, penutupan kloter dan kalkulasi ekonomi tetap ditambahkan melalui modul produksinya setelah kontrak dan keputusan terkait tersedia.

## Endpoint

Semua endpoint memakai prefix:

```text
/tenants/:tenantId/factories/:factoryId
```

| Metode dan path | Fungsi |
| --- | --- |
| `POST /suppliers` | Membuat pemasok tenant |
| `GET /suppliers` | Daftar/pencarian pemasok tenant |
| `GET /suppliers/:supplierId` | Detail pemasok |
| `PATCH /suppliers/:supplierId` | Mengubah nama atau status aktif |
| `GET /suppliers/:supplierId/history` | Riwayat perubahan pemasok yang berasal dari pabrik pada URL |
| `POST /lots` | Membuat identitas dasar kloter |
| `GET /lots` | Daftar/pencarian kloter pada pabrik |
| `GET /lots/:lotId` | Detail kloter dan nama pemasok saat ini |
| `PATCH /lots/:lotId` | Koreksi metadata dasar kloter |
| `GET /lots/:lotId/history` | Riwayat perubahan kloter |

Guard autentikasi dan akses tetap digunakan. Jangan menambahkan bypass auth untuk onboarding yang belum tersedia. Cara menguji tanpa akun dijelaskan di bawah.

### Membuat pemasok

```json
{ "name": "Pemasok Sintetis A" }
```

Respons `201` berisi `id`, `tenantId`, `name`, `isActive`, `createdAt` dan `updatedAt`. Pemasok baru aktif secara default. Contoh PATCH:

```json
{ "name": "Pemasok Sintetis A Baru", "isActive": false }
```

Nama wajib berisi 1–200 karakter setelah trim, tanpa karakter kontrol. `isActive` harus berupa boolean, bukan string.

### Membuat kloter

```json
{
  "supplierId": "40000000-0000-4000-8000-000000000001",
  "receivedAt": "2026-11-16T08:00:00+07:00",
  "displayCode": "DEMO-MANUAL-01"
}
```

Ganti `supplierId` dengan UUID pemasok yang tersedia. Respons `201` berisi `id`, `tenantId`, `factoryId`, `supplierId`, `supplierName`, `displayCode`, `receivedAt`, `createdAt` dan `updatedAt`.

`receivedAt` wajib berupa ISO 8601 dengan zona waktu eksplisit; contoh di atas dikembalikan sebagai `2026-11-16T01:00:00.000Z`. Tanggal kalender tidak valid dan waktu tanpa zona ditolak. Batas periode/shift pabrik belum ditetapkan oleh modul ini.

`displayCode` berisi 1–100 karakter atau `null`. Contoh PATCH untuk menghapus kode manual:

```json
{ "displayCode": null }
```

PATCH juga menerima `receivedAt` dan `supplierId`. Pemasok pengganti harus aktif dalam tenant yang sama; metadata lain pada kloter lama tetap dapat dikoreksi ketika pemasok asal sudah nonaktif. Nama pemasok pada detail kloter adalah nama master saat ini; riwayat nama master dapat dilihat melalui audit pemasok sesuai cakupan pabrik.

Setelah kloter memiliki penerimaan sah, perubahan pemasok/waktu penerimaan melalui endpoint metadata ditolak 409. Koreksi kode tampil tetap tersedia; koreksi data resmi perlu workflow dokumen dan penyesuaian stok.

### Daftar, pencarian dan pagination

Respons daftar/history:

```json
{ "items": [], "total": 0, "limit": 20, "offset": 0 }
```

`total` tetap menyatakan seluruh hasil filter meskipun offset melewati halaman terakhir. Filter dan halaman dibaca dari satu snapshot query.

| Query | Pemasok | Kloter |
| --- | --- | --- |
| `q` | Substring nama | Substring kode tampil atau nama pemasok |
| `isActive=true/false` | Filter status; bawaan menampilkan semua | — |
| `supplierId` | — | UUID pemasok |
| `receivedFrom` | — | Waktu mulai, inklusif |
| `receivedBefore` | — | Waktu akhir, eksklusif |
| `limit` | 1–100; bawaan 20 | 1–100; bawaan 20 |
| `offset` | Bilangan bulat nonnegatif; bawaan 0 | Bilangan bulat nonnegatif; bawaan 0 |

`q` tidak membedakan huruf besar/kecil dan memperlakukan `%`/`_` sebagai teks biasa. History menerima `limit`/`offset` saja. Waktu query harus di-URL-encode, terutama tanda `+` pada offset zona waktu.

Contoh:

```text
GET /suppliers?q=Sintetis&isActive=true&limit=20&offset=0
GET /lots?receivedFrom=2026-11-16T00:00:00Z&receivedBefore=2026-11-17T00:00:00Z
```

History berisi `id`, `action`, `actorId`, `before`, `after` dan `occurredAt`. Riwayat pemasok dibatasi pada pabrik asal perubahan, meskipun master pemasoknya dibagikan dalam tenant. Snapshot kloter menyimpan referensi pemasok, bukan salinan nama pemasok.

### Validasi dan error

Field di luar kontrak, termasuk `tenantId`, `factoryId`, role, status pengesahan dan berat produksi, ditolak dengan `400`. Tenant, pabrik dan actor selalu diambil dari konteks akses backend. Body PATCH kosong juga ditolak.

- `400`: input/filter salah atau pemasok tidak tersedia untuk pembuatan kloter.
- `401`/`403`: token atau akses cakupan tidak memenuhi kebijakan.
- `404`: resource tidak ditemukan dalam cakupan; PATCH kloter juga menolak relasi pemasok pengganti yang tidak memenuhi syarat dengan respons generik ini.
- `503`: database/provider tidak tersedia.

Pengecekan cakupan diulang dalam statement query, termasuk ketika menulis. Composite foreign key melindungi relasi tenant–pabrik–pemasok. Ketiga tabel baru mengaktifkan RLS dan tidak memberi akses langsung kepada role Supabase `anon`/`authenticated`.

## Migrasi dan pengujian tanpa onboarding

Dari `apps/api`:

```powershell
npm run db:migrate
npm test
npm run test:production-db
```

Migrasi `002_suppliers_lots.sql` menambahkan `sobatnira.suppliers`, `sobatnira.lots` dan `sobatnira.production_audit_events`. Semua perubahan schema mengikuti runner migrasi berversi yang sudah ada.

`npm test` menjalankan validasi input dan pemeriksaan backend lokal tanpa akun cloud. `test:production-db` menggunakan PostgreSQL dari `.env`, Supabase Auth tiruan lokal, serta tenant/pabrik/user sintetis dalam transaksi yang selalu di-rollback. Tidak ada akun permanen, signup API atau pengiriman email. Pemeriksaan ini dapat dijalankan sebelum onboarding tersedia.

Tes integrasi mencakup alur HTTP tambah/baca/ubah/history, pemakaian pemasok antar pabrik satu tenant, penolakan resource lintas tenant/pabrik, pagination kosong, filter waktu, pemasok nonaktif, relasi database, pencabutan akses dan pembatalan perubahan saat audit gagal. Bila migrasi 002 belum diterapkan, tes memeriksanya terlebih dahulu dalam transaksi sementara; jalankan `db:migrate` untuk menerapkannya secara permanen pada development.

Fixture Auth hanya dibuat jika belum ada trigger aplikasi pada `auth.users` yang perlu diperiksa. Token tiruan hanya diterima server Auth lokal milik tes dan tidak menambahkan jalur masuk khusus pada aplikasi.

Flutter saat ini masih memakai data lokal untuk Beranda/Kloter. Penyambungan UI ke kontrak ini dilakukan terpisah. Alur [dokumen penerimaan dan pengesahan](backend-intake-documents.md) sudah menghubungkan catatan penerimaan sintetis ke identitas kloter ini.
