# Kontrak nira dan penutupan kloter untuk Backend B

Semua rute Backend A di bawah diawali `/tenants/{tenantId}/factories/{factoryId}/lots/{lotId}`. Gunakan `Authorization: Bearer <access_token Supabase>`. A memeriksa ulang akses admin atau owner pada pabrik. ID kloter dan batch berupa UUID. `batchId` adalah referensi milik B dan B bertanggung jawab memastikan batch tersebut sah.

Setelah menjalankan `npm run db:migrate` di `apps/api`, uji alur dengan `npm run test:juice-db`. Fixture PostgreSQL memakai akun, nota, dan data sintetis; panggilan Backend B dalam tes diarahkan ke server lokal tiruan.

## Detail kloter untuk Backend B

Panggil `GET /tenants/{tenantId}/factories/{factoryId}/lots/{lotId}` dengan access token pengguna. Respons memuat `id`, `tenantId`, `factoryId`, `supplierId`, `supplierName`, `displayCode`, dan `receivedAt` dari kloter.

| Field | Arti |
| --- | --- |
| `synthetic` | Kategori data yang diminta. Bawaan `false`. Gunakan `?synthetic=true` untuk fixture. |
| `netWeightGrams` | Berat penerimaan yang sudah sah dalam gram, berupa string desimal eksak atau `null` sebelum penerimaan sah. Contoh 1250,01 kg menjadi `"1250010"`. Nilai ini tetap menunjukkan berat penerimaan setelah tebu digiling. |
| `status`, `closureId`, `closedAt`, `closedBy` | Status pada kategori yang diminta. Kloter yang terbuka mengembalikan ketiga field penutupan sebagai `null`. |
| `intake`, `milling` | `null` atau objek `{id, approvedAt, document}` untuk penerimaan dan penggilingan yang sudah dibukukan. |
| `document` | `{source, documentId, revisionId, revisionNumber}`. Sumber `ocr` membawa UUID revisi sah pada `revisionId`. Sumber `synthetic` membawa nomor revisi sah pada `revisionNumber`. Field revisi yang tidak dipakai bernilai `null`. |

Backend B bisa memeriksa `intake` dan `milling` untuk mengetahui tahap yang sudah sah, sedangkan `status` mengikuti penutupan kloter. Gunakan `/juice/availability` untuk saldo nira yang dapat direservasi.

## Saldo dan reservasi

| Method dan path | Request atau hasil |
| --- | --- |
| `GET /juice/availability?synthetic=true` | `lotId`, `synthetic`, `unit: "ml"`, `onHandMl`, `reservedMl`, `availableMl`, dan `origins` |
| `POST /juice/reservations` | Body `{requestId, batchId, quantityMl, originLotId?, synthetic?}`. Hasil berisi data reservasi, `state`, dan metadata audit. |
| `POST /juice/reservations/{requestId}/consume` | Mengubah `reserved` ke `consumed` dan mendebit stok fisik. |
| `POST /juice/reservations/{requestId}/release` | Mengubah `reserved` ke `released` dan mengembalikan jatah ke saldo tersedia. |

`quantityMl` berupa string desimal positif, misalnya `"20000"` untuk 20 L. Liter dari penggilingan sah dikonversi dengan faktor 1000 di PostgreSQL tanpa pembulatan. `synthetic` bawaan `false`; di body gunakan boolean dan di query gunakan `true` atau `false`. Saldo sintetis terpisah dari saldo riil.

`availableMl = onHandMl - reservedMl`. `origins` merinci ketiganya per `originLotId`. Default `originLotId` pada reservasi adalah kloter pada path. Untuk nira titipan, pilih kloter asal yang ditampilkan di `origins`. Satu reservasi memakai satu sumber. Jika satu batch perlu beberapa sumber, gunakan ID permintaan berbeda per sumber dan lepaskan reservasi yang sudah berhasil jika tahap reservasi berikutnya gagal.

Simpan `requestId` sebelum memanggil A. Retry dengan input yang sama mengembalikan state terbaru dari transaksi yang sama. Payload berbeda dengan kunci yang sama dalam operasi dan pabrik yang sama menghasilkan 409. Retry `consume` atau `release` yang sama mengembalikan hasil tersimpan. Aksi akhir yang berlawanan menghasilkan 409. Reservasi aktif tetap ditahan sampai dikonsumsi atau dilepas. B perlu menyimpan ID reservasi bersama batch agar bisa melanjutkan retry setelah restart.

A mengunci kloter di PostgreSQL sebelum memeriksa saldo dan menulis transaksi. Reservasi atau transfer yang melebihi saldo tersedia ditolak. Endpoint lama `GET /stock/juice` tetap memberi total hasil penggilingan dalam liter. Gunakan `/juice/availability` untuk saldo yang memperhitungkan pemakaian dan transfer.

## Transfer

`POST /juice/transfers` menerima `{requestId, toLotId, quantityMl, originLotId?, synthetic?}`. Kloter pada path adalah kloter yang memegang stok saat ini. Dua kloter harus berbeda dan berada dalam satu tenant serta pabrik. Transfer mengurangi saldo sumber dan menambah saldo tujuan dalam satu transaksi. `originLotId` tetap sama saat nira ditransfer lagi. Jika tidak diisi, nilainya mengikuti kloter pada path.

Contoh alur sintetis dengan satuan ml. Kloter A menghasilkan 250000. Setelah dua batch mengonsumsi masing-masing 115000, transfer 20000 ke kloter B. Bila batch penerima memakai 80000 nira B dan 20000 nira titipan A, buat dua reservasi di kloter B dengan `originLotId` masing-masing. Aturan izin transfer lintas pabrik perlu keputusan tim.

### Transfer dari Flutter

Pada mode terhubung, pilih pabrik lalu buka detail kloter dan **Transfer nira**. Pilih asal nira yang memiliki saldo tersedia, pilih kloter tujuan dalam pabrik yang sama, lalu isi volume dalam liter. Pemilih tujuan mendukung pencarian dan halaman berikutnya serta mengecualikan kloter pemegang stok. API memeriksa kembali saldo dan status kedua kloter saat mencatat transfer.

Form menerima koma atau titik desimal. Konversi liter ke string mililiter menjaga angka desimal secara eksak. Saldo sumber yang dipakai untuk validasi adalah nira tersedia per asal, yang sudah memperhitungkan reservasi. Setelah berhasil, halaman menampilkan bukti transfer dan ID permintaan. Kembali ke detail untuk memuat saldo terbaru.

Jika respons terputus, gunakan **Coba lagi transfer yang sama**. UUID dan payload dipertahankan selama sesi login, termasuk saat halaman ditutup dan dibuka lagi. Kiriman yang belum mendapat hasil pasti menampilkan ringkasan dengan input terkunci. Simpan ID permintaan bila perlu keluar dari sesi untuk pemeriksaan transaksi. Penolakan format atau konflik (`400`/`409`) memungkinkan pengguna memperbaiki input dan membuat permintaan baru setelah saldo dimuat ulang.

Uji form sampai PostgreSQL melalui `node scripts/mobile-production-fixture.cjs --transfer` dari `apps/api` dengan database lokal khusus pengujian. Tambahkan `--dart-define=PRODUCTION_TEST_TRANSFER_LOT=UUID_ASAL`, `--dart-define=PRODUCTION_TEST_TRANSFER_TO=UUID_TUJUAN`, dan `--dart-define=PRODUCTION_TEST_TRANSFER_THIRD=UUID_KETIGA` dari keluaran server ke [perintah tes mobile](backend-production-basics.md#pengelolaan-melalui-flutter). Skenario memakai fixture rollback, menguji saldo eksak, replay UUID, dan transfer lanjutan dengan asal nira yang dipertahankan.

## Penutupan kloter

- `GET /closure?synthetic=true` memberi `status: "open" | "closed"`, `closureId`, `closedAt`, dan `closedBy`.
- `POST /closure` menerima body opsional `{synthetic: true}` dan mengembalikan status penutupan. Prasyarat lokal adalah penggilingan sah, saldo di kloter sudah nol, dan tidak ada reservasi aktif.
- A memanggil `GET /batches/closure-check/{kloterId}?tenantId=…&factoryId=…&synthetic=…` dengan access token pemanggil. Respons yang dibutuhkan adalah HTTP 200 dengan `{"canClose":true}` atau `{"canClose":false}`. B memvalidasi akses tenant/pabrik dan menilai kesiapan penutupan berdasarkan catatan batch yang sah. Jalur ini harus baca saja dan tidak meminta operasi yang mengunci kloter yang sama.
- Bila B mengembalikan `false`, A merespons 409. Jika konfigurasi kosong, B gagal, mencapai timeout, atau bentuk respons tidak sesuai, A merespons 503. Kloter tetap terbuka. Format respons dan penerusan Bearer diuji dengan fixture dan perlu dicocokkan dengan implementasi B sebelum integrasi nyata.
- Saat B menyetujui, A menulis status tutup di bawah kunci kloter. Retry mengembalikan penutup yang sama. Setelah tutup, A menolak reservasi atau transfer baru yang melibatkan saldo kloter tersebut. Status tutup memakai kategori sintetis atau riil yang sama dengan ledger. Penutupan saldo kloter sumber tidak menutup pemakaian nira asalnya yang sudah dipindahkan ke kloter lain.
- Agar pemeriksaan tetap konsisten, semua pemakaian batch baru harus melewati reservasi A dan B harus memperlakukan reservasi sebagai prasyarat pencatatan pemakaian. Pemeriksaan HTTP B tidak membuat transaksi lintas layanan.

### Buka kembali dan riwayat

- Terapkan migrasi `015_lot_reopening.sql` sebelum menjalankan API baru. Migrasi memberi UUID pada penutupan yang sudah ada dan menambahkan penyimpanan riwayat buka kembali.
- `POST /closure/reopen` menerima `{closureId, reason, synthetic?}`. Ambil `closureId` dari status penutupan aktif pada kategori yang sama. Admin dan owner di pabrik tersebut dapat membuka kembali dengan alasan 1–500 karakter. Respons `200` berisi `{lotId, synthetic, closureId, reopenedBy, reopenedAt, reason}`. Panggil `GET /closure` untuk memuat status terkini.
- Kiriman ulang dengan ID penutupan dan alasan yang sama mengembalikan bukti buka kembali sebelumnya, termasuk jika kloter telah ditutup ulang. ID yang tidak sesuai atau alasan berbeda menghasilkan `409`. ID lama tidak dapat digunakan untuk membuka penutupan baru.
- `GET /closure/history?synthetic=true&limit=20&offset=0` memberi `items`, `total`, `limit`, dan `offset`. Setiap item memuat `id` penutupan, `closedBy`, `closedAt`, `reopenedBy`, `reopenedAt`, dan `reason`. Data buka kembali bernilai `null` selama penutupan masih aktif. Riwayat mengikuti kategori riil atau sintetis yang dipilih.
- Buka kembali mengubah status kloter dan mencatat audit dalam satu transaksi. Saldo, reservasi, transfer, dan revisi dokumen tetap mengikuti catatan semula. Penutupan ulang memakai `closureId` baru serta menjalankan lagi pengecekan saldo dan Backend B.

### Penggunaan dari Flutter

Pada mode terhubung, pilih pabrik, buka detail kloter, lalu pilih **Penutupan dan riwayat**. Halaman memuat status aktif serta riwayat dari API dalam kategori riil. **Tutup kloter** meminta konfirmasi dan menjalankan pemeriksaan backend. **Buka kembali kloter** meminta alasan sebelum mengirim UUID penutupan yang sedang ditampilkan. Setelah tindakan, halaman mengambil ulang status dan riwayat. Ketika kembali ke detail, detail kloter juga dimuat ulang.

Riwayat menampilkan waktu dan ID pelaku penutupan, serta waktu, pelaku, dan alasan buka kembali. Waktu mengikuti zona perangkat. Gunakan **Sebelumnya** dan **Berikutnya** untuk membaca halaman riwayat lain. Penolakan pemeriksaan batch atau stok ditampilkan di halaman. Permintaan dengan respons terputus diikuti pembacaan ulang status dan riwayat sebelum tindakan berikutnya.

Untuk menguji form sampai PostgreSQL, gunakan [server fixture mobile](backend-production-basics.md#pengelolaan-melalui-flutter) dengan `node scripts/mobile-production-fixture.cjs --closure` dari `apps/api`. Selain URL dan cakupan, server mencetak `PRODUCTION_TEST_CLOSURE_LOT`. Tambahkan `--dart-define=PRODUCTION_TEST_CLOSURE_LOT=UUID_KLOTER` ke perintah tes Flutter yang sama. Fixture memakai identitas sintetis, penggilingan dan batch sah di PostgreSQL dalam transaksi rollback. Skenario memeriksa penolakan kloter tanpa penggilingan, penutupan kloter dengan saldo habis, buka kembali dengan alasan, riwayat, serta penutupan ulang.

Penutupan operasional memeriksa batch di PostgreSQL dari NestJS. Untuk fixture sintetis yang masih menggunakan kontrak lama di lingkungan development atau test, `BATCH_API_BASE_URL` menerima origin Backend B dengan batas waktu bawaan 3000 ms. Jalur API penyimpanan tetap dibatasi role dan cakupan pabrik.
