# Data dasar pemasok, jenis tebu, dan kloter

Modul ini menyediakan metadata pemasok, katalog jenis tebu, dan identitas kloter. Pengujian modul menggunakan identitas dan data sintetis.

## Cakupan

- Pemasok berada pada tingkat tenant dan dapat dipakai oleh beberapa pabrik dalam tenant tersebut.
- Kloter berada pada satu tenant/pabrik dan merujuk pemasok dalam tenant yang sama.
- Admin dan owner dengan membership aktif dapat mengelola metadata dalam cakupannya.
- Setiap pembuatan/perubahan dicatat bersama actor, waktu dan snapshot sebelum/sesudah dalam satu statement database yang atomik.
- Pemasok dapat dinonaktifkan. Pemasok nonaktif tidak dapat dipilih untuk kloter baru; kloter lama tetap dapat dibaca.
- Tidak ada endpoint penghapusan fisik pemasok atau kloter.

Kloter menggunakan UUID internal. `displayCode` bersifat opsional dan diisi manual; sistem belum menghasilkan format/suffix resmi atau memakai kode untuk pencocokan otomatis. Dua kiriman dengan kode tampilan yang sama tetap memiliki UUID berbeda. Nama pemasok juga tidak dijadikan identitas unik.

Endpoint metadata dasar tidak mencatat berat, Brix atau pengesahan. Gunakan [modul dokumen penerimaan](backend-intake-documents.md) untuk mengesahkan draf penerimaan dan membukukan stok tebu masuk, lalu [modul nota hasil penggilingan](backend-milling-documents.md) untuk pemakaian seluruh tebu kloter dan pencatatan total nira serta rincian batch yang dilaporkan. Ledger pemasakan, batch resmi, penutupan kloter dan kalkulasi ekonomi mengikuti modul berikutnya.

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
| `GET /cane-types` | Daftar jenis tebu tenant dengan pencarian dan filter status |
| `POST /cane-types` | Membuat jenis tebu tenant |
| `GET /cane-types/:caneTypeId` | Detail jenis tebu |
| `PATCH /cane-types/:caneTypeId` | Mengubah nama atau status aktif |
| `GET /cane-types/:caneTypeId/history` | Riwayat jenis tebu dari pabrik pada URL |
| `POST /lots` | Membuat identitas dasar kloter |
| `GET /lots` | Daftar/pencarian kloter pada pabrik |
| `GET /lots/:lotId` | Detail kloter, pemasok, berat resmi, penutupan, dan referensi revisi sah. Lihat [kontrak detail kloter](backend-juice-and-closure.md#detail-kloter-untuk-backend-b). |
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

### Mengelola katalog jenis tebu

Terapkan migrasi `016_cane_type_catalog.sql`. Admin dan owner dengan membership aktif dapat mengelola katalog tenant melalui pabrik pada URL. Pabrik dalam tenant yang sama memakai katalog yang sama.

```json
{ "code": "DEMO-01", "name": "Jenis Tebu Uji" }
```

`POST /cane-types` mengembalikan `201` dengan `id`, `tenantId`, `code`, `name`, `isActive`, `createdAt`, dan `updatedAt`. Kode terdiri dari 1–40 huruf ASCII, angka, tanda hubung, atau garis bawah. Kode katalog disimpan dalam huruf kapital dan unik per tenant. Kode yang sudah terdaftar menghasilkan `409`.

`PATCH` menerima `name` dan `isActive`. Kode tetap menjadi identitas katalog setelah jenis tebu dibuat. Gunakan `isActive: false` untuk menonaktifkan pilihan. Pengulangan PATCH dengan nilai yang sama mengembalikan item yang sama tanpa menambah riwayat.

Gunakan `GET /cane-types?q=demo&isActive=true&limit=20&offset=0` untuk pilihan aktif. `q` mencocokkan bagian kode atau nama tanpa membedakan kapitalisasi. Riwayat mengikuti pabrik asal perubahan dan mencatat snapshot sebelum dan sesudah.

Katalog bisa digunakan sebagai sumber pilihan jenis tebu. Pengesahan penerimaan saat ini menyimpan kode `caneTypeCode` pada revisi nota sesuai validasi format yang sudah ada. Data katalog diisi oleh tenant sesuai jenis tebu yang dipakai.

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

### Pengelolaan melalui Flutter

Pada mode terhubung, masuk ke aplikasi lalu pilih pabrik. Tombol **Pemasok** dan **Jenis tebu** membuka daftar dari API tenant. Cari data atau filter status, lalu gunakan tombol tambah atau buka item untuk mengubah nama dan status aktif. Saat membuat jenis tebu, isi juga kode. Kode jenis tebu tampil pada form edit.

Gunakan **Tambah kloter** untuk memilih pemasok aktif serta waktu penerimaan sesuai zona waktu perangkat. Pemilih pemasok mendukung pencarian dan perpindahan halaman. Kode kloter bersifat opsional. Setelah disimpan, daftar dimuat ulang dari API. Untuk mengedit kloter, buka detail lalu pilih ikon **Edit kloter**. Pemasok dan waktu penerimaan terkunci ketika detail sudah memuat penerimaan sah. Backend memeriksa lagi kondisi tersebut saat menyimpan, termasuk bila pengesahan terjadi ketika form masih terbuka.

Pengujian widget dengan API tiruan dijalankan melalui `flutter test test/features/kloter/production_management_test.dart`. Untuk memeriksa form sampai PostgreSQL, siapkan database lokal khusus pengujian dengan schema auth sintetis serta migrasi bisnis 001–016. Dari `apps/api`, set `TEST_DATABASE_URL` ke database loopback tersebut lalu jalankan `node scripts/mobile-production-fixture.cjs`. Server mencetak URL serta UUID tenant dan pabrik sintetis untuk perintah berikut dari `apps/mobile`.

```sh
flutter test --dart-define=PRODUCTION_TEST_API=http://127.0.0.1:PORT --dart-define=PRODUCTION_TEST_TENANT=UUID_TENANT --dart-define=PRODUCTION_TEST_FACTORY=UUID_PABRIK test/features/kloter/production_backend_test.dart
```

Isi ketiga nilai dari keluaran server fixture. Uji membuat dan mengubah pemasok, menonaktifkan jenis tebu, serta membuat dan mengubah kloter melalui form Flutter. Periksa hasil lewat endpoint API dan riwayat PostgreSQL. Hentikan server dengan Ctrl+C untuk rollback data sintetis. Uji ini dilewati pada `flutter test` biasa bila URL fixture belum diisi.

### Pengujian API

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


### Ringkasan kloter untuk Flutter

Tambahkan `includeSummary=true` pada daftar kloter untuk meminta status penutupan, berat bersih penerimaan dalam gram, Brix, kode jenis tebu, volume nira yang diproduksi dalam liter, dan referensi penerimaan serta penggilingan yang disahkan. Field yang belum dibukukan bernilai `null`. Ringkasan membaca volume nira hasil rekonsiliasi terbaru dan tidak mencakup saldo, reservasi, batch resmi, harga, atau margin. Detail kloter mengembalikan field ringkasan yang sama. Scope pabrik, filter, urutan, dan paginasi daftar tetap berlaku.
