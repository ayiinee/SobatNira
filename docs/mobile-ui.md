# Penyelarasan tampilan mobile

Penyelarasan ini mencakup Beranda, Kloter, detail kloter/batch, Laporan, Pengaturan, serta tema komponen pada Pekerjaan dan Detail Nota. Adapter mempertahankan kompatibilitas baca API batch lama tanpa menambahkan aksi tulis yang tidak didukung backend.

## Acuan demo dan sumber data

Acuan visual adalah `feat/repair-connected-ui`, commit desain `e44730a` milik Putu Alvin. Perbaikan integrasi pada `59d9ba3` serta pembacaan detail batch API lama dari `97f044d` tetap dipertahankan. Kartu kloter menampilkan badge status di samping ID, kemudian pemasok, berat dan tanggal; kartu batch menampilkan judul serta badge di atas nira dan hasil fisik. Warna, ilustrasi, dan tombol pembatalan validasi berwarna merah mengikuti desain tersebut. Pada layar sempit atau teks besar, teks dapat membungkus. Status juga tersedia melalui semantik aksesibilitas.

Akses Pekerjaan berada di Pengaturan. Beranda tidak menambah tombol kedua di bawah empat pintasan. Panel Tinjau/Tuntas menampilkan keterangan saat kosong, tanpa menampilkan keterangan kosong selama status pemuatan atau kegagalan masih aktif.

Grafik Grade menggunakan seluruh kode dari data backend untuk legenda, batang bertumpuk, dan detail interaktif. Grafik Margin memakai skala ribuan rupiah: nilai nonnol di bawah Rp1.000 tetap ditulis sebagai pecahan, misalnya Rp500 menjadi `0,500`. Format nominal resmi pada kartu, tabel dan PDF tetap berasal dari string API.

Demo dan Supabase memakai urutan field proses, ringkasan batch, tab Masak, serta tabel Grade yang sama melalui `detail_fields.dart`. Adapter hanya mengisi nilai yang tersedia dari API. Jam turun, bagian kloter, operator, takaran bahan, atau harga grade yang belum dikirim API ditampilkan sebagai `—`; angka demo tidak digunakan sebagai pengganti data backend. Margin kloter berasal dari snapshot laporan, dan volume batch dikonversi tepat dari mL ke L tanpa pembulatan tambahan.

Area pratinjau nota mempertahankan rasio 2,4:1 saat foto sah belum tersedia, dengan tautan menuju Pekerjaan. Foto contoh hanya digunakan dalam demo. Biaya, reservasi dan pengesahan tetap memakai endpoint serta otorisasi resmi; detail batch sah tidak mengulang panel status biaya draf.

## Tipografi

Font tetap Inter. Ukuran dipusatkan di `NiraType` dalam `apps/mobile/lib/sobatnira_ui.dart`.

| Ukuran | Penggunaan |
| --- | --- |
| 12 | Tanggal, keterangan pendukung, label metrik, badge dan label navigasi |
| 14 | Isi utama, data tabel, label form, tombol dan tab |
| 16 | Judul bagian, judul kartu dan identitas pada daftar |
| 20 | Judul halaman, identitas detail dan angka pada panel metrik sempit |
| 24 | Angka kartu ringkasan |
| 32 | Angka utama Keuntungan di Beranda |

Tinggi baris isi adalah 1,4 dan teks berukuran 20 ke atas adalah 1,2. Teks isi memakai regular; label dan judul bagian memakai medium/semibold; judul serta angka utama memakai bold sesuai kebutuhan penekanan. Komponen Material pada Pekerjaan mendapat ukuran dari `niraTheme()` yang sama.

## Tata letak

- `NiraSpace`: 4, 8, 12, 16, dan 24. Jarak kecil untuk label/nilai; jarak besar untuk pergantian bagian.
- Margin horizontal halaman tetap 30. Padding kartu/form umumnya 12–16. Radius kartu dan input adalah 8; navigasi dan profil tetap berbentuk pil.
- Pengaturan memakai ikon 24 dalam wadah 40, judul menu 14 dan keterangan 12. Setiap baris memiliki ruang vertikal untuk deskripsi yang membungkus.
- Header detail tidak mendapat margin ganda ketika berada di dalam daftar yang sudah memiliki padding.
- Area konten halaman utama berakhir sebelum navigasi bawah agar item terakhir bisa digulir dan disentuh.
- Input dan tombol mengikuti tema bersama. Baris edit data minimal setinggi 48; tinggi baris tabel dapat bertambah mengikuti isinya.

## Kartu dan ilustrasi

Overlay kartu ringkasan Beranda tetap 80 × 80 dengan posisi yang sama. Gambar tebu kartu kloter menjadi 120 × 73; kartu batch memakai 104 × 63. Keduanya ditempatkan di kanan bawah dengan clipping. Opacity ilustrasi mengikuti komponen bersama `KloterCaneOverlay` (0,77 untuk tinjauan dan 0,50 untuk tuntas). Teks kartu kloter tinjauan tetap putih di atas warna emas, sesuai arahan tampilan.

Saat teks diperbesar, kartu ringkasan dapat disusun vertikal, empat aksi Beranda berubah menjadi dua kolom, tanggal kloter berpindah ke bawah ID, dan informasi batch berpindah ke bawah judul. Kartu batch hanya menampilkan nira batch dan hasil fisik; baris bagian dari kloter dihapus dari ringkasan kartu. Panel metrik menambah baris berdasarkan lebar tersedia dan pembesaran teks. Nilai laporan tidak lagi dikecilkan memakai `FittedBox` agar muat dalam kartu sempit.

## Verifikasi

- Seluruh 103 tes Flutter lulus; dua tes integrasi memerlukan fixture layanan tersendiri. Cakupannya meliputi navigasi, detail kloter/batch, otorisasi aksi, status, pembesaran teks, panel kosong di layar normal/kecil, serta kompatibilitas pagination API lama.
- Dua puluh skenario pada ukuran 430 × 950 dibandingkan dengan render commit desain `e44730a`: halaman utama, detail proses, tiga tab batch, laporan dan ekspor, termasuk grade tambahan serta margin Rp500. Tidak ada perbedaan piksel di atas ambang 10 per kanal warna. Pemeriksaan ini memakai renderer tes Flutter, bukan perangkat Android.
- Tes grafik memeriksa segmen grade tambahan yang benar-benar digambar dan tooltip-nya, serta label margin pecahan.
- `flutter analyze --no-pub` tidak menemukan masalah.
- Integrasi laporan Flutter → NestJS → PostgreSQL lulus menggunakan fixture sintetis dalam transaksi yang di-rollback setelah tes.

Ukuran ini menjadi dasar bersama. Penyesuaian berikutnya sebaiknya mengikuti fungsi teks/komponen, bukan menambahkan ukuran pecahan untuk tiap halaman.

Mode demo langsung membuka Beranda dengan fixture. Mode terhubung membuka sambutan dan login email, lalu memeriksa akses pabrik dan membuka Beranda yang sama dengan navigasi **Beranda**, **Kloter**, **Laporan**, dan **Pengaturan**. Gunakan pemilih pabrik di profil Beranda ketika akun memiliki beberapa pabrik. Saat keluar dari Pengaturan atau ketika sesi berakhir, aplikasi kembali ke form masuk.

Dalam mode terhubung, buka **Pengaturan → Pekerjaan** untuk melihat antrean, foto, bukti, dan revisi nota pada pabrik aktif. Setelah validasi, kembali ke Beranda untuk melihat kartu kloter dan Rekap Produksi yang sudah dimuat ulang. Rekap mengunduh penerimaan dan penggilingan yang disahkan. Laba, biaya, gula final, grade, dan batch resmi memakai status **Belum tersedia** sampai sumber datanya tersedia.
