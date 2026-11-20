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

Saat teks diperbesar, kartu ringkasan dapat disusun vertikal, empat aksi Beranda berubah menjadi dua kolom, tanggal kloter berpindah ke bawah ID, dan informasi batch berpindah ke bawah judul. Kartu batch hanya menampilkan nira batch dan hasil fisik; baris bagian dari kloter dihapus dari ringkasan kartu. Panel metrik menambah baris berdasarkan lebar tersedia dan pembesaran teks.

## Angka panjang dan kestabilan kartu

Pada lebar layar dan pembesaran teks yang sama, perubahan jumlah digit tidak mengubah tinggi kartu ringkasan maupun panel metrik. Pasangan kartu memakai ruang label yang sama. Tinggi tetap menyesuaikan pembesaran teks untuk aksesibilitas; pada layar sempit pasangan kartu dapat disusun vertikal.

`NiraValue` menampilkan angka dalam satu baris tanpa mengecilkan font. Angka ringkasan hanya disingkat bila nilai lengkap tidak muat, menggunakan ribu/juta/miliar/triliun, lalu bentuk pendek atau notasi ilmiah jika ruang masih terbatas. Pemendekan ini perkiraan untuk presentasi, bukan nilai perhitungan. Ketuk angka yang dipendekkan untuk membuka nilai lengkap yang dapat disalin. Tooltip dan semantik aksesibilitas juga memakai nilai lengkap.

Field proses, harga per grade, rincian biaya, serta baris ekspor mempertahankan string lengkap. Jika terlalu panjang, angka dapat digeser mendatar dan dibuka dalam dialog. Ketukan pada field demo yang dapat diedit tetap membuka editor. Angka lengkap dari API, snapshot perhitungan, serta data PDF tidak diubah oleh formatter tampilan; pemendekan menggunakan operasi string agar digit di atas batas integer JavaScript tetap tersimpan utuh.

Grafik membatasi label ke ruang sumbu atau slot batang dan menyingkat tick besar. Grafik produksi mengurangi kepadatan label tanggal pada periode panjang. Detail sentuhan berada di bawah plot agar tidak terpotong; margin yang dipilih menampilkan nominal rupiah lengkap. Plot mengikuti pembesaran teks. Rekap batch yang lebar tetap memakai tabel dengan scroll horizontal.

## Verifikasi

- Tes kestabilan ukuran menggunakan Inter asli pada lebar 320, 360, dan 430, dengan teks 100%, 150%, dan 200%. Nilai meliputi nol, jutaan, triliunan, angka negatif, pecahan panjang, serta digit di atas batas integer JavaScript. Tes dialog memeriksa string lengkap yang dapat disalin, dan field edit tetap membuka editor.
- Regresi halaman mencakup Beranda, Produksi/Margin, tiga detail laporan, dua ekspor (termasuk rekap dibuka), detail kloter, dua tab proses, serta tiga tab batch: 14 alur pada dua lebar dan dua skala teks. Tes canvas memeriksa label grafik tidak melewati batas plot.
- Audit render memakai 60 skenario komponen dan 18 tampilan Beranda/Laporan, dengan Inter asli. Pada layar 430 dan teks 100%, kartu produksi tetap 82 px dan kartu nominal tetap 77 px untuk seluruh panjang angka yang diuji. Pemeriksaan ini memakai renderer tes Flutter, bukan perangkat Android.
- Acuan desain awal telah dibandingkan pada 20 skenario dengan `e44730a`. Penyesuaian angka panjang sengaja mengubah format ringkasan, ukuran ruang label grafik, dan letak detail interaktif.
- `flutter analyze --no-pub` tidak menemukan masalah.
- Integrasi laporan Flutter → NestJS → PostgreSQL lulus menggunakan fixture sintetis dalam transaksi yang di-rollback setelah tes.

Ukuran ini menjadi dasar bersama. Penyesuaian berikutnya sebaiknya mengikuti fungsi teks/komponen, bukan menambahkan ukuran pecahan untuk tiap halaman.

Mode demo langsung membuka Beranda dengan fixture. Mode terhubung membuka sambutan dan login email, lalu memeriksa akses pabrik dan membuka Beranda yang sama dengan navigasi **Beranda**, **Kloter**, **Laporan**, dan **Pengaturan**. Gunakan pemilih pabrik di profil Beranda ketika akun memiliki beberapa pabrik. Saat keluar dari Pengaturan atau ketika sesi berakhir, aplikasi kembali ke form masuk.

Dalam mode terhubung, buka **Pengaturan → Pekerjaan** untuk melihat antrean, foto, bukti, dan revisi nota pada pabrik aktif. Setelah validasi, kembali ke Beranda untuk melihat kartu kloter dan Rekap Produksi yang sudah dimuat ulang. Rekap mengunduh penerimaan dan penggilingan yang disahkan. Laba, biaya, gula final, grade, dan batch resmi memakai status **Belum tersedia** sampai sumber datanya tersedia.
