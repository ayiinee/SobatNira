# Acuan proyek SobatNira

SobatNira membantu pabrik gula merah tebu menelusuri hasil produksi kembali ke bahan baku dan bukti pencatatannya. Panduan ini merangkum konteks yang dapat dibagikan dari SobatNira Knowledge Pack v1.0, dikonsolidasikan pada 16 November 2026.

## Alur produksi

1. **Penerimaan tebu.** Catat penerimaan dan penimbangan bahan baku.
2. **Penggilingan.** Catat nira yang dihasilkan dari tebu yang digiling.
3. **Pengolahan dan pemasakan.** Lacak nira yang digunakan dalam proses pemasakan.
4. **Penimbangan hasil.** Catat berat gula yang dihasilkan.
5. **Grading.** Catat mutu hasil dan hubungkan dengan hasil penimbangan.

**Kloter** mengelompokkan tebu masuk untuk pelacakan bahan baku. **Batch** mengidentifikasi proses pemasakan dan hasil yang terkait. Rujuk register keputusan internal untuk menentukan cara mencocokkan dokumen atau menghubungkan data produksi.

Klarifikasi alur pencatatan: lima tahap produksi tersebut berasal dari dua nota fisik, yaitu nota truk masuk dan nota hasil produksi gabungan. Nota kedua mencakup total nira per kloter, pembagian batch, hingga hasil akhir. Tiga wajan berkapasitas awal sekitar 115 L dapat dipakai berulang; jumlah batch satu kloter dapat lebih dari tiga. Nira campuran tetap perlu ditelusuri ke kloter asalnya.

## Cakupan AI Engineering

Baseline AI Engineering memprioritaskan alur foto nota melalui WhatsApp, ekstraksi draf, konfirmasi operator atas revisi tertentu, lalu peninjauan dan validasi oleh admin atau owner di Flutter. Cakupan awal OCR mencakup **Nota Kedatangan Truk** dan **Nota Produksi**. Nota Produksi dapat diperbarui lewat pengiriman foto berikutnya. Lima tahap fisik di atas tetap menjadi konteks proses.

Kontrak dan kriteria penerimaan terperinci tersedia di paket PRD internal tim.

## Tanggung jawab layanan dan status implementasi

| Layanan | Tanggung jawab | Yang tersedia di repo |
| --- | --- | --- |
| Flutter | Antarmuka admin dan owner untuk melihat serta meninjau data. | Onboarding, Beranda, Kloter, Laporan, dan Pengaturan memakai simulasi lokal. Pekerjaan memakai API review saat autentikasi dikonfigurasi. |
| NestJS | Otorisasi, validasi domain, dan kalkulasi resmi. | Intake satu foto, penyimpanan privat, pekerjaan OCR, revisi, serta konfirmasi dan review berbasis PostgreSQL. Modul produksi menangani pemasok, kloter, penerimaan, bukti R2, dan pembukuan penggilingan sintetis. |
| FastAPI | Pemrosesan AI internal dan keluaran draf ekstraksi. | Ekstraksi draf dua tipe nota dengan PaddleOCR, parser dan evidence. Gemini dapat dikonfigurasi untuk crop ambigu. |

[Panduan intake AI](ai/README.md) menjelaskan setup bridge OpenClaw/Baileys, database, dan layar Pekerjaan. [Demo integrasi lokal](development.md#jalankan-integrasi-di-tiga-terminal) tetap tersedia dengan `lib/main_demo.dart` dan menampilkan fixture dari FastAPI melalui NestJS.

Pengesahan nota truk di Pekerjaan mencatat penerimaan resmi dan stok tebu per kloter. Saat mengesahkan nota produksi, peninjau memilih kloter per blok tebu lalu mengisi volume nira dan waktu penggilingan. NestJS membukukan debit tebu dan kredit nira dari revisi yang disahkan. Lihat [penerimaan dari nota OCR](backend-intake-documents.md#penerimaan-dari-nota-ocr) dan [alur penggilingan](backend-milling-documents.md).

## Menggunakan acuan tim

- Untuk perilaku yang tersedia sekarang, periksa kode, tes, dan [panduan setup](development.md).
- Untuk aturan produksi, periksa register keputusan internal. Knowledge Pack menandai keputusan yang berlaku dengan `[DECIDED]`. Konfirmasi butir `[OPEN]` atau `[CONFLICT]` dengan pemilik keputusan. Temuan lapangan, contoh sintetis, dan referensi desain memberi konteks untuk pembahasan aturan.
- Anggota tim dapat meminta Knowledge Pack melalui kanal berbagi privat tim. Simpan acuan internal di `docs/internal/`, yang diabaikan Git. Ikuti [panduan kontribusi](contributing.md) saat mendokumentasikan keputusan dan perubahan lintas layanan.
