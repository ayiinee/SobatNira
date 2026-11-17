# Penyelarasan tampilan mobile

Penyelarasan ini mencakup Beranda, Kloter, detail kloter/batch, Laporan, Pengaturan, serta tema komponen pada Pekerjaan dan Detail Nota. Perubahan hanya menyentuh presentasi dan penyesuaian tes antarmuka.

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

Overlay kartu ringkasan Beranda tetap 80 × 80 dengan posisi yang sama. Gambar tebu kartu kloter menjadi 120 × 73; kartu batch memakai 104 × 63. Keduanya ditempatkan di kanan bawah dengan clipping. Opacity gambar dikurangi menjadi 0,65 pada kartu tinjauan dan 0,30 pada kartu tuntas. Teks kartu kloter tinjauan tetap putih di atas warna emas, sesuai arahan tampilan.

Saat teks diperbesar, kartu ringkasan dapat disusun vertikal, empat aksi Beranda berubah menjadi dua kolom, tanggal kloter berpindah ke bawah ID, dan informasi batch berpindah ke bawah judul. Kartu batch hanya menampilkan nira batch dan hasil fisik; baris bagian dari kloter dihapus dari ringkasan kartu. Panel metrik menambah baris berdasarkan lebar tersedia dan pembesaran teks. Nilai laporan tidak lagi dikecilkan memakai `FittedBox` agar muat dalam kartu sempit.

## Verifikasi

- Seluruh 15 tes Flutter lulus, termasuk startup langsung ke Beranda, navigasi/state tab, filter, edit/verifikasi, Pekerjaan dengan API sintetis, serta penyimpanan harga lokal.
- Render offline tujuh halaman pada lebar 360 dan 393, masing-masing dengan pembesaran teks 100% dan 150%: 28 kombinasi tanpa exception layout.
- Hasil render normal dan pembesaran diperiksa secara visual. Pemeriksaan ini memakai renderer tes Flutter, bukan browser atau perangkat Android.
- `flutter analyze` tidak menemukan error atau warning; SDK melaporkan info deprecation untuk impor `material.dart` yang sudah digunakan proyek.

Ukuran ini menjadi dasar bersama. Penyesuaian berikutnya sebaiknya mengikuti fungsi teks/komponen, bukan menambahkan ukuran pecahan untuk tiap halaman.

Onboarding dan login demo dinonaktifkan sementara dari alur aplikasi. Aplikasi langsung membuka Beranda. Autentikasi API Pekerjaan tetap mengikuti konfigurasi dan izin backend.

Navbar utama berisi empat menu: Beranda, Kloter, Laporan, dan Pengaturan. Tombol Pekerjaan di Beranda membuka antrean review nota. Sesi review tersimpan selama halaman Pekerjaan terbuka. Header detail menggunakan panah kembali yang dirapatkan secara konsisten ke margin kiri konten.
