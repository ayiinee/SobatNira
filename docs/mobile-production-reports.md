# Ringkasan dan laporan produksi terhubung

Beranda, tab Produksi/Margin, pintasan Laba/Rekap, serta detail kloter, grade dan batch memakai sumber laporan yang sama. Tidak diperlukan migrasi baru; laporan membaca penerimaan, batch dan snapshot produksi yang sudah tersedia.

## Sumber dan batas perhitungan

- `GET /tenants/:tenantId/factories/:factoryId/production/production-report` memerlukan Bearer token serta membership admin/owner di pabrik tersebut.
- Parameter `from` inklusif dan `before` eksklusif mengikuti **waktu penerimaan kloter**, sama dengan laporan laba yang sudah ada. Flutter mengubah pilihan tanggal lokal menjadi batas waktu UTC; akhir periode adalah awal hari berikutnya.
- Tebu diterima dan jumlah kloter hanya menghitung penerimaan sah. Kloter tanpa penerimaan sah tidak dihitung. Penerimaan sah tanpa hasil produksi tetap ditampilkan, dengan hasil/margin belum tercatat.
- Gula final, nilai produksi, biaya dan margin memakai **snapshot kumulatif terbaru per kloter**, sehingga biaya tidak dihitung lagi untuk setiap snapshot. Total batch hanya mencakup batch sah. Draf/cancelled tidak menjadi hasil resmi.
- Nilai grade dan batch berasal dari berat serta harga tersimpan pada batch sah. Kode grade asli dipertahankan. Nilai detail ini ditampilkan sebelum pembulatan per kloter; total nilai produksi/margin tetap mengikuti snapshot resmi HALF_UP.
- Keputusan pengguna pada 19 November 2026: Detail Batch menampilkan **nilai produksi batch** dan **margin kumulatif kloter**, bukan mengasumsikan pembagian biaya per batch. Margin kloter dapat sementara karena memakai seluruh biaya kloter dengan hasil batch yang sudah sah. Ini bukan laba bersih penjualan.
- `synthetic=false` menjadi bawaan. Pilihan **Tampilkan data contoh** mengganti kategori secara eksplisit, tanpa mencampur data riil dan sintetis. Periode/kategori dibagi bersama oleh Beranda, Laporan dan pintasan selama sesi pabrik aktif. Berpindah pabrik membuat state baru.

Respons berisi `items` (identitas kloter, penerimaan, snapshot, batch sah beserta grade), `grades`, dan `totals` (jumlah kloter diterima/menghasilkan, batch, tebu, gula, nilai, biaya, margin). Angka berat dan rupiah berupa string desimal. API memakai BigInt untuk uang dan aritmetika desimal; Flutter memformat string tanpa konversi rupiah ke floating point. Kode tampilan sama tetap dibedakan melalui UUID kloter.

Satu statement PostgreSQL membaca semua bagian laporan dalam snapshot baca yang sama. Loading/error mengosongkan nilai lama, menyediakan tombol coba lagi, dan tidak mengubah kegagalan menjadi nilai nol. Respons lama setelah pergantian periode tidak menimpa respons yang lebih baru.

## Layar dan ekspor

Mode terhubung dan demo memakai `LaporanPage`, `ReportDetailPage`, dan `ReportExportPage` yang sama. Data dari API mengisi kartu ringkasan, grafik Produksi dan Margin, tabel, serta hasil ekspor pada komponen tersebut. `BatchDetailPage` juga memakai tab Ringkasan, Masak, dan Grade yang sama untuk kedua sumber data.

Beranda memakai total laporan dan menyediakan pemilih periode di baris kalender. Tab Laporan menyediakan pilihan periode/data contoh, total produksi atau margin, daftar kloter dan kontribusi grade. Buka kloter untuk rincian rendemen/biaya serta batch sah; Detail Kloter juga membuka rincian produksi tersebut. Pintasan Laba dan Rekap memakai state laporan yang sama.

Rekap memuat gula, margin, jumlah dan rincian batch sah. Tampilan dan PDF menerima snapshot objek yang sama, termasuk nominal total eksak, identitas kloter duplikat dan kode batch. Nilai yang belum tercatat tidak diperkirakan. Laporan laba tetap mempertahankan nama produk tersebut, dengan isi berupa margin produksi kumulatif.

Demo offline tetap memakai fixture sintetis yang sudah ada. Ringkasan demo kini menjumlahkan sumber analitik dan Detail Batch menghitung nilai dari berat/grade demo, menggantikan nominal keuntungan/margin batch yang tetap. Demo tidak menjadi bukti transaksi backend.

## Verifikasi

- `npm test` dari `apps/api`: validasi periode/kategori, angka besar eksak, grade, margin negatif dan data kosong.
- `node --test test/integration/batches-database.test.cjs` setelah build: fixture PostgreSQL rollback memeriksa pengesahan, harga, batas waktu, isolasi pabrik/kategori dan pengecualian draf. Muat environment development sesuai lokasi `.env`; path CA relatif harus disesuaikan dengan lokasi konfigurasi API.
- `flutter analyze --no-fatal-infos` dan `flutter test` dari `apps/mobile`: alur login–Beranda–pintasan, laporan/detail, periode, respons terlambat/error, PDF, identitas duplikat dan tata letak layar kecil.

Untuk uji Flutter → NestJS → PostgreSQL, jalankan `node --env-file=../../.env scripts/mobile-report-fixture.cjs` dari `apps/api` dengan konfigurasi database development dan CA yang benar. Simpan JSON `REPORT_TEST_*` yang dicetak ke `.tmp/mobile/report-test-defines.json` di akar repo. Lalu dari `apps/mobile`, jalankan:

```powershell
flutter test --no-pub test/features/laporan/report_backend_test.dart --dart-define-from-file=../../.tmp/mobile/report-test-defines.json
```

Fixture membuat batch dan pengesahan melalui HTTP pada transaksi rollback, lalu Flutter membaca dan menampilkan angka yang sama. Ketik `stop` pada terminal fixture setelah tes agar transaksi di-rollback dan koneksi ditutup. Tes ini dilewati oleh suite biasa jika konfigurasi fixture tidak diberikan.

Jalankan ulang NestJS dan Flutter dari source terbaru. Tidak ada perubahan skema, deployment atau seed yang diperlukan oleh laporan ini.
