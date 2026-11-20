# Keputusan arsitektur implementasi AI

## Aplikasi dan data resmi

- Flutter tim tetap dijalankan melalui `apps/mobile/lib/main.dart`. Acceptance memakai bundle web acuan dan satu origin browser di port 8000.
- NestJS memverifikasi actor, role dan pabrik, mengelola pekerjaan OCR, perubahan stok, pengesahan, serta snapshot kalkulasi. FastAPI menghasilkan draf. OpenClaw tetap mengatur percakapan.
- Capture dan Validation memakai alur persisten yang sudah ada. Traceability, Analytics, dan bagian baca Reporting tersedia sebagai operasi NestJS. Keputusan pengesahan dan mutasi stok tetap di workflow yang sudah ada.
- Ringkasan, grade, metrik, dan data sumber laporan memakai query yang sama dengan Laporan Flutter. Gunakan ID snapshot kalkulasi untuk menelusuri angka. Rekap mempertahankan bentuk respons lama, dengan snapshot kumulatif terakhir yang sama per kloter. API B1 memakai model penyimpanan tersendiri dan dipertahankan untuk caller lama.
- Kontribusi batch menyajikan debit nira yang tercatat. `originLotId` dan `stockLotId` bisa berbeda setelah transfer. Pertanyaan gabungan memakai satu pembacaan PostgreSQL untuk total, distribusi grade, dan peringkat yang diminta secara eksplisit. Peringkat ditahan jika jumlah debit per batch berbeda dari volume batch sah. Pertanyaan tanpa dasar peringkat meminta klarifikasi. Alokasi biaya campuran, harga efektif, dan rendemen agregat mengikuti register keputusan.

## Revisi nota dan pengukuran

- Quote yang berhasil diverifikasi di percakapan dan pabrik yang sama tetap mendukung serah terima operator. Referensi UUID tanpa quote dan foto ulang memakai operator serta percakapan dari submission aktif. Kandidat yang dikirim mengikuti batas tersebut. Konfirmasi dan jawaban tetap mengikuti revisi dan pertanyaan aktif dengan penolakan untuk pesan lama.
- Parser membedakan sel kosong ketika header, baris, dan bukti piksel cukup. Kasus terpotong, buram, atau belum bisa dipastikan tetap mengikuti jalur pemeriksaan. Bukti OCR serta status disimpan per revisi.
- Median berdasarkan sampel yang tercatat. Benchmark menahan p95 ketika grup dokumen independen di bawah 100. Sampel sintetis mengukur regresi. Pilot partner dan holdout memerlukan dataset berizin.
- Untuk Gemini selective reread, hanya simpan versi prompt, nama model dan penggunaan token numerik dari respons yang tersedia. Jika data tagihan belum tersedia, biaya tetap tidak terisi.

## Akses capability dan POC

- API baca memakai guard owner dan membership pabrik. NestJS dapat menerbitkan kode sekali pakai bagi owner yang meminta sambungan ke nomor tertentu. Adapter hanya menyerahkan event percakapan langsung dengan token internal. Kode dan nomor disimpan sebagai digest. Scope dibaca ulang dari membership setiap kali. Jalur WhatsApp owner memerlukan opt-in dan verifikasi staging sebelum aktivasi.
- OpenRouter dapat membantu memilih intent jika aturan chat belum mengenalinya. Saat owner meminta penjelasan, model memilih fokus dari daftar terbatas dengan hanya menerima status kelengkapan. NestJS menjalankan operasi dan template chat merender nilai serta keterbatasan resmi. Tanggal dihitung dari event provider dalam WIB. Nomor, token, referensi entitas, dan angka hasil tetap di luar input OpenRouter.
- Report request membekukan hasil query resmi. Worker PostgreSQL memakai lease, tiga percobaan, dan kunci artefak yang stabil. PDF dan XLSX diverifikasi sebelum transaksi menyatakan `READY` dan mengantrikan notifikasi. Target notifikasi dienkripsi, lalu diotorisasi kembali ketika diklaim oleh adapter. Status dan unduhan tetap dibatasi pemohon owner yang aktif.
- Langflow POC terisolasi di `tools/langflow-poc`. Proses gateway loopback memegang token owner sintetis, mengikat scope ke fixture, dan hanya meneruskan pembacaan `get_production_insight`. NestJS melakukan verifikasi akhir. Komponen POC berjalan deterministik tanpa model dan tanpa koneksi langsung ke PostgreSQL.
- Gunakan [register keputusan yang dibutuhkan](DECISIONS_REQUIRED.md) untuk gap yang tersisa dan [kontrak capability](CAPABILITY_API.md) untuk integrasi.
