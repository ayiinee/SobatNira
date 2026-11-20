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

Flutter mode terhubung membaca Beranda/Kloter melalui API. Demo offline tetap
memakai data lokal. Alur [dokumen penerimaan dan pengesahan](backend-intake-documents.md)
menghubungkan catatan penerimaan ke identitas kloter ini.


## Pagination dan ringkasan kloter

Lihat [checklist optimisasi](optimization-checklist.md) untuk status implementasi,
integrasi Flutter, pengukuran dan pekerjaan lanjutan.

### Pagination cursor (tahap optimisasi backend)

Daftar `GET /tenants/:tenantId/factories/:factoryId/lots` mendukung mode opt-in
`pagination=cursor&limit=50&includeSummary=true`. Respons berbentuk
`{ items, limit, nextCursor }`, tanpa total dan offset. Kirim `after=<nextCursor>`
untuk halaman berikutnya dengan filter yang sama; `nextCursor: null` menandai akhir.
`offset` tidak boleh digabung dengan mode cursor. Tanpa `pagination=cursor`, respons
lama `{ items, total, limit, offset }` tetap berlaku.

Urutan tetap `received_at DESC, id ASC`. Cursor mempertahankan mikrodetik PostgreSQL
agar waktu yang sama atau berbeda kurang dari satu milidetik tidak melewatkan data.
Cursor hanya batas pencarian, bukan otorisasi: membership dan scope tetap diperiksa
pada setiap query. Mulai ulang dari halaman pertama setelah filter/pabrik berubah.
Pagination bukan snapshot lintas-request; perubahan tanggal kloter selama penelusuran
dapat memindahkan baris ke halaman lain.

Mode cursor menghindari `COUNT(*)` dan memakai indeks `lots_factory_received_idx`
yang sudah tersedia; tidak ada migrasi indeks tambahan pada tahap ini. Flutter
mode terhubung memakai cursor dengan 30 item per request, filter server dan counts
terpisah. Beranda, daftar Kloter dan pilihan kloter Biaya Ops mempunyai pager sendiri.
Mode demo offline mempertahankan pagination lokal berdasarkan tanggal.

### Filter status, pencarian dan hitungan badge

Daftar menerima `status=open` atau `status=closed` pada mode cursor maupun offset.
`closed` mengikuti penutupan aktif dengan kategori sintetis/resmi yang sama, bukan
sekadar semua batch sudah sah. Penutupan yang dibuka kembali tidak dihitung tertutup.
Tanpa parameter status, daftar tetap menampilkan seluruh status.

Mode opsional `searchMode=normalized&q=...` mencari kode/UUID tanpa membedakan
huruf besar, spasi dan tanda hubung; nama pemasok tetap dicari sebagai substring
tanpa membedakan huruf besar. Mode pencarian lama tetap berlaku jika `searchMode`
tidak dikirim. Token normalisasi kosong tidak mencocokkan seluruh kode/UUID.
Karakter `%` dan `_` tetap literal, bukan wildcard. Urutan hasil tetap tanggal/ID;
ranking saran tersedia melalui endpoint di bawah.

`GET /tenants/:tenantId/factories/:factoryId/lots/counts` mengembalikan
`{ total, open, closed }` untuk seluruh data yang cocok, tanpa mengunduh halaman.
Filter yang didukung: `q`, `searchMode`, `supplierId`, `receivedFrom`,
`receivedBefore`, `synthetic`. Filter waktu tetap interval `[receivedFrom, receivedBefore)`
dengan timestamp berzona; klien harus memakai batas hari dari zona waktu tampilan.
Endpoint counts menolak `status` dan parameter pagination agar angka semua tab dapat
dipakai bersama. Panggil ulang counts saat filter berubah, bukan per halaman cursor.

Counts dan daftar memakai filter/scope bersama. Otorisasi tetap membutuhkan admin
atau owner aktif. Query counts memakai satu snapshot PostgreSQL untuk ketiga angka;
request daftar dan counts yang terpisah dapat melihat perubahan yang terjadi di
antaranya. Angka ini hanya jumlah kloter, bukan ringkasan berat, stok atau margin
Beranda. Total berat, jumlah kloter berproduksi dan margin tetap berasal dari laporan
lengkap dengan periode yang berlaku, bukan dijumlahkan dari halaman daftar.

`GET /lots/suggestions` pada prefix pabrik yang sama menerima `q` wajib, `status`,
`supplierId`, `receivedFrom`, `receivedBefore`, `synthetic` dan `limit` (maksimum
efektif 5). Hasil `{ items }` diperingkat kecocokan kode/UUID: exact (rank 0),
prefix (1), substring (2), lalu kode dan ID. Pencarian mencakup semua data yang
cocok dalam scope, bukan hanya halaman cursor yang sudah dimuat. Kecocokan nama
pemasok saja tidak menjadi saran kode. Memilih saran memakai `lotId` pada daftar
dan counts agar kode sama di dua kloter tidak memilih record yang salah.

Flutter membentuk batas awal hari dan awal hari berikutnya dalam zona waktu
perangkat, lalu mengirim keduanya sebagai UTC. Pengelompokan tampilan memakai
`receivedAt.toLocal()` pada zona waktu yang sama. Kalender membuat hari berikutnya
dengan konstruktor tanggal, bukan menambah 24 jam, agar batas DST tetap benar.
Satu hari boleh berlanjut ke halaman berikutnya; baris digabung per tanggal dan ID,
dan header bertanda `dimuat` selama masih ada halaman. Header tersebut bukan
klaim jumlah seluruh kloter pada hari itu.

Pencarian/status/tanggal reset cursor. Respons dari query lama atau pager yang
sudah dibuang diabaikan. Halaman berikutnya ditambahkan tanpa mengosongkan daftar;
scroll dekat akhir dan tombol **Muat kloter berikutnya** berbagi guard permintaan.
Error halaman berikutnya mempertahankan baris, posisi scroll, dan cursor retry.
Tarik untuk refresh memuat ulang hanya jumlah halaman yang pernah dibuka, bukan
seluruh isi pabrik. Perubahan kategori sintetis atau pabrik membersihkan scope lama.

Sesudah validasi/koreksi/buang draf, pembaruan daftar dijalankan setelah operasi
berhasil dan pengguna kembali dari detail batch; transfer dan penutupan memberi
notifikasi setelah operasi berhasil. Kegagalan transport batch juga menandai daftar
untuk disegarkan setelah kembali, sebab COMMIT mungkin sudah berhasil. Beranda,
badge, daftar Kloter yang sudah
dibuka dan laporan disegarkan; detail batch tetap mempunyai jalur baca sendiri.
Perubahan biaya juga tidak memakai daftar Beranda yang terpotong untuk memilih kloter.

Urutan rilis: deploy API cursor/counts/suggestions terlebih dahulu, kemudian Flutter.
Klien Flutter baru memerlukan kontrak tersebut; endpoint offset tetap tersedia bagi
klien lama. Rollback Flutter tidak memerlukan rollback schema pagination.

### Uji Flutter hingga PostgreSQL

Dengan PostgreSQL lokal khusus data sintetis dan migrasi bisnis/Auth fixture yang
sudah disiapkan, dari `apps/api` jalankan:

```powershell
$env:TEST_DATABASE_URL = 'postgres://postgres@127.0.0.1:55449/postgres'
node scripts/mobile-production-fixture.cjs --pagination
```

Fixture menambahkan 65 kloter bertanda `PAG-`, termasuk 16 penutupan aktif, dalam
transaksi rollback. Gunakan tiga nilai `PRODUCTION_TEST_*` yang dicetak server untuk
menjalankan dari `apps/mobile`:

```powershell
flutter test test/features/kloter/lot_pagination_backend_test.dart --dart-define=PRODUCTION_TEST_API=<URL-fixture> --dart-define=PRODUCTION_TEST_TENANT=<tenant-fixture> --dart-define=PRODUCTION_TEST_FACTORY=<pabrik-fixture>
```

Mulai fixture baru untuk setiap putaran tes, lalu hentikan dengan Ctrl+C untuk
rollback. Tes memeriksa 30/60/65 baris tanpa duplikasi, saran di luar halaman awal,
pilihan ID, counts lengkap, batas hari lokal, pembukaan kembali kloter, refresh
setelah penambahan data dan penolakan scope lain. Tes ini sengaja dilewati pada
suite standar jika URL fixture tidak diberikan. Jika C: sempit, arahkan `TEMP` dan
`TMP` proses Flutter ke direktori sementara di D:.

Verifikasi filter/counts pada 20 November 2026: build dan 87 tes backend/integrasi
lulus tanpa skip pada PostgreSQL sintetis dengan runner berurutan. Tes HTTP
mencakup filter cursor/offset, normalisasi, counts seluruh hasil, penutupan yang
dibuka kembali, pemisahan kategori, isolasi pabrik, akses anonim dan membership dicabut.

### Mengukur query daftar dengan fixture bervolume

Gunakan database lokal khusus bernama `sobatnira_perf_*`, dengan schema Auth sintetis
dan migrasi bisnis seperti lingkungan CI. Jangan gunakan database demo/tim. Dari
`apps/api`, set `PERF_DATABASE_URL` ke database tersebut, lalu jalankan
`npm run perf:lots`. Opsional `PERF_LOTS=20000` (rentang 1000–100000).

Skrip menambahkan kloter sintetis melalui transaksi rollback, menjalankan query
repository asli untuk offset/cursor halaman awal/jauh, dan merekam lima sampel
`EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`. Rencana lengkap tersimpan di
`.tmp/performance/lots-query-profile.json` di akar repo, di luar Git. Data fixture
dibatalkan setelah selesai. `ANALYZE` dapat mengubah statistik database uji sehingga
database wajib disposable. Pengukuran tidak memakai R2/AI atau akun cloud.

Hasil lokal 20 November 2026, 20.000 kloter dan 50 item per halaman:

| Query | Median waktu eksekusi |
| --- | --- |
| Offset halaman awal | 53,564 ms |
| Offset halaman jauh (16.000) | 108,159 ms |
| Cursor halaman awal | 1,545 ms |
| Cursor halaman jauh | 1,592 ms |

Pada query cursor halaman jauh, indeks kloter membaca 51 baris hasil dan menyaring
satu baris batas. Hasil ini mencakup penghilangan perhitungan total dan perubahan
query, bukan manfaat cursor saja. Ini lima sampel query hangat pada satu koneksi,
tanpa biaya jaringan/Auth, persaingan koneksi, atau kepadatan nota/batch produksi;
bukan jaminan latensi aplikasi produksi.

Verifikasi tahap ini: build TypeScript dan 86 tes backend/integrasi lulus dengan
PostgreSQL sintetis, memakai
`node --test --test-concurrency=1 test/*.test.cjs test/integration/production-database.test.cjs`.
Tes mencakup timestamp sama, mikrodetik, akhir halaman, filter kosong, isolasi pabrik,
validasi cursor dan kompatibilitas respons offset lama.

### Field ringkasan

Tambahkan `includeSummary=true` pada daftar kloter untuk meminta status penutupan, berat bersih penerimaan dalam gram, Brix, kode jenis tebu, volume nira yang diproduksi dalam liter, dan referensi penerimaan serta penggilingan yang disahkan. Field yang belum dibukukan bernilai `null`. Ringkasan membaca volume nira hasil rekonsiliasi terbaru dan tidak mencakup saldo, reservasi, batch resmi, harga, atau margin. Detail kloter mengembalikan field ringkasan yang sama. Scope pabrik, filter, urutan, dan paginasi daftar tetap berlaku.
