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

## Tanggung jawab layanan dan status implementasi

| Layanan | Tanggung jawab | Yang tersedia di repo |
| --- | --- | --- |
| Flutter | Antarmuka admin dan owner untuk melihat serta meninjau data. | Beranda, Kloter, Laporan, dan Pengaturan memakai simulasi lokal. Demo integrasi tersedia melalui `lib/main_demo.dart`. |
| NestJS | Otorisasi, validasi domain, dan kalkulasi resmi. | Health/demo, konfigurasi cloud, akses Supabase per tenant/pabrik, pemasok/kloter, pengesahan penerimaan dan foto R2 privat, serta penggilingan sintetis dari nota hasil gabungan. Onboarding dan proses produksi berikutnya belum lengkap. |
| FastAPI | Pemrosesan AI internal dan keluaran draf ekstraksi. | Endpoint health dan satu draf sintetis melalui `GET /demo/draft`. |

OCR nota dan klarifikasi lewat WhatsApp masih dalam pengembangan. Modul bisnis menyimpan data di PostgreSQL dengan migrasi dan audit. [Penggilingan](backend-milling-documents.md) membukukan tebu dan nira setelah pengesahan admin; rincian batch pada nota masih berupa observasi, sementara ledger pemasakan, hasil timbang, dan grade resmi mengikuti tahap berikutnya. Dalam [demo integrasi lokal](development.md#jalankan-integrasi-di-tiga-terminal), Flutter mengambil draf melalui NestJS dan menampilkan hasil fixture dari FastAPI; layar produksi utama masih simulasi lokal.

## Menggunakan acuan tim

- Untuk perilaku yang tersedia sekarang, periksa kode, tes, dan [panduan setup](development.md).
- Untuk aturan produksi, periksa register keputusan internal. Knowledge Pack menandai keputusan yang berlaku dengan `[DECIDED]`. Konfirmasi butir `[OPEN]` atau `[CONFLICT]` dengan pemilik keputusan. Temuan lapangan, contoh sintetis, dan referensi desain memberi konteks untuk pembahasan aturan.
- Anggota tim dapat meminta Knowledge Pack melalui kanal berbagi privat tim. Simpan acuan internal di `docs/internal/`, yang diabaikan Git. Ikuti [panduan kontribusi](contributing.md) saat mendokumentasikan keputusan dan perubahan lintas layanan.
