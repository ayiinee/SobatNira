# Acuan proyek SobatNira

SobatNira membantu pabrik gula merah tebu menelusuri hasil produksi kembali ke bahan baku dan bukti pencatatannya. Panduan ini merangkum konteks yang dapat dibagikan dari SobatNira Knowledge Pack v1.0, dikonsolidasikan pada 16 November 2026.

## Alur produksi

1. **Penerimaan tebu.** Catat penerimaan dan penimbangan bahan baku.
2. **Penggilingan.** Catat nira yang dihasilkan dari tebu yang digiling.
3. **Pengolahan dan pemasakan.** Lacak nira yang digunakan dalam proses pemasakan.
4. **Penimbangan hasil.** Catat berat gula yang dihasilkan.
5. **Grading.** Catat mutu hasil dan hubungkan dengan hasil penimbangan.

**Kloter** mengelompokkan tebu masuk untuk pelacakan bahan baku. **Batch** mengidentifikasi proses pemasakan dan hasil yang terkait. Rujuk register keputusan internal untuk menentukan cara mencocokkan dokumen atau menghubungkan data produksi.

## Tanggung jawab layanan dan status implementasi

| Layanan | Tanggung jawab | Yang tersedia di repo |
| --- | --- | --- |
| Flutter | Antarmuka admin dan owner untuk melihat serta meninjau data. | Beranda, Kloter, Laporan, dan Pengaturan memakai simulasi lokal. Demo integrasi tersedia melalui `lib/main_demo.dart`. |
| NestJS | Otorisasi, validasi domain, dan kalkulasi resmi. | Endpoint health dan penerusan `GET /demo/draft` ke FastAPI. |
| FastAPI | Pemrosesan AI internal dan keluaran draf ekstraksi. | Endpoint health dan satu draf sintetis melalui `GET /demo/draft`. |

OCR nota, klarifikasi lewat WhatsApp, dan penyimpanan data produksi ada dalam rancangan. Dalam [demo integrasi lokal](development.md#jalankan-integrasi-di-tiga-terminal), Flutter mengambil draf melalui NestJS dan menampilkan hasil fixture dari FastAPI.

## Menggunakan acuan tim

- Untuk perilaku yang tersedia sekarang, periksa kode, tes, dan [panduan setup](development.md).
- Untuk aturan produksi, periksa register keputusan internal. Knowledge Pack menandai keputusan yang berlaku dengan `[DECIDED]`. Konfirmasi butir `[OPEN]` atau `[CONFLICT]` dengan pemilik keputusan. Temuan lapangan, contoh sintetis, dan referensi desain memberi konteks untuk pembahasan aturan.
- Anggota tim dapat meminta Knowledge Pack melalui kanal berbagi privat tim. Simpan acuan internal di `docs/internal/`, yang diabaikan Git. Ikuti [panduan kontribusi](contributing.md) saat mendokumentasikan keputusan dan perubahan lintas layanan.
