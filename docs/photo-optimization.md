# Foto: validasi, preview dan thumbnail

Sumber asli tetap disimpan tanpa resize/re-encode dan tetap menjadi masukan OCR.
Keputusan retensi saat ini hanya simulasi; tahap ini tidak menghapus bukti, EXIF pada
sumber asli, revisi historis atau objek storage. Tidak ada migrasi schema.

## Upload

Upload WhatsApp dan bukti penerimaan kini menggunakan decoder/validator yang sama
sebelum penyimpanan permanen: signature dan MIME sesuai, maksimal 8 MiB, maksimal
20 juta piksel, decode penuh dan gambar statis satu frame. APNG ditolak lewat chunk
`acTL` karena decoder PNG dapat hanya membaca frame pertama. WebP animasi juga
ditolak. Kontrak WhatsApp tetap JPEG/PNG; bukti penerimaan tetap JPEG/PNG/WebP.
Perbedaan daftar format tersebut dipertahankan sesuai kontrak layanan AI.

Validasi berada di batas HTTP WhatsApp sebelum transaksi/manifest/upload. Caller
internal yang memanggil `Intake.photo` langsung bertanggung jawab melewati validasi
yang sama. SHA-256, ukuran dan dimensi sumber asli tetap dicatat lewat jalur lama.

## Membaca varian

| Parameter | Perilaku |
| --- | --- |
| tanpa parameter atau `variant=original` | Byte asli, MIME asli |
| `variant=preview` | Maksimal 2048 × 2048, fit inside, tanpa memperbesar |
| `variant=thumbnail` | Maksimal 320 × 320, fit inside, tanpa memperbesar |

Parameter berlaku pada endpoint konten evidence penerimaan dan
`/api/v1/mobile/review-tasks/:taskId/assets/:assetId`. Parameter tidak dikenal
menghasilkan 400. Autentikasi dan lookup referensi/membership tetap dilakukan sebelum
storage dibaca; varian memakai hak akses yang sama dengan sumber, termasuk sumber
revisi historis. Respons tetap `private, no-store` dan `nosniff`.

Preview/thumbnail menggunakan **WebP lossless, effort 2**. Lossless berlaku pada hasil
resize; resize sendiri mengurangi piksel bila sumber melampaui batas. Tidak ada
jaminan setiap gambar lebih kecil dari sumber JPEG. Respons varian maksimal 8 MiB;
kegagalan pembuatan/integritas mengembalikan 503 dan UI menawarkan sumber asli.
Hash dan ukuran sumber diverifikasi sebelum gambar dikirim, termasuk jalur internal
AI. SHA-256, dimensi dan versi transformasi (`raw-axes-webp-lossless-v1`) dihitung pada
hasil helper; belum ada registry turunan persisten.

Sharp membuang EXIF/GPS/ICC pada varian tampilan. Transformasi tidak melakukan
auto-orient, rotate atau crop: koordinat OCR `ORIGINAL_IMAGE_NORMALIZED` mengacu pada
sumbu piksel mentah yang dipakai layanan AI. Resize proporsional mempertahankan bbox
ternormalisasi. Foto dengan EXIF orientation dapat terlihat berbeda dari pembaca
yang melakukan auto-rotate; jangan mengaktifkan auto-orient tanpa memetakan bbox.
Tes marker piksel dengan EXIF orientation 6 memeriksa sumbu dan posisi tersebut.

Flutter Pekerjaan meminta preview untuk tampilan dengan overlay. **Buka foto asli**
baru mengunduh sumber saat ditekan, lalu menyediakan zoom tanpa overlay. Tombol
tetap tersedia bila preview gagal. Sumber asli tidak ditampilkan otomatis sebagai
pengganti preview; review dapat membukanya untuk angka kecil atau bukti yang kabur.
Endpoint internal OCR selalu memakai sumber asli; tidak menerima parameter varian.

Foto nota sah pada tab proses Kloter dan Detail Batch juga meminta preview. Menekan
foto/tombol perbesar baru menjalankan loader asli dengan scope pabrik/revisi yang
sama. Dialog menampilkan loading, error dan retry; retry gagal berulang tidak
menghasilkan exception yang tidak ditangani. Jalur demo dan pemanggil helper lama
tetap tersedia tanpa loader tambahan. Pengujian memeriksa tidak ada unduh asli saat
preview pertama tampil dan filter pabrik/revisi tetap dikirim.

## Resource dan storage

Satu limiter per proses NestJS digunakan bersama oleh decode upload, pembacaan foto
asli dan transformasi: satu pekerjaan aktif, maksimal empat menunggu, kelebihan
menghasilkan 503. Slot diambil sebelum membaca storage; exception selalu melepas
slot. Pemrosesan native Sharp diberi timeout 10 detik (waktu menunggu thread libuv
tidak termasuk). Batas ini bukan hasil sizing produksi atau deadline seluruh HTTP.

Body multipart sudah berada di memori sebelum validasi dan output dapat menunggu
pengiriman ke klien sesudah slot dilepas; limiter bukan batas RAM keras seluruh
aplikasi. Setiap sumber dibatasi 8 MiB dan piksel dibatasi, tetapi decode native juga
memerlukan memori. Sampling RSS sesudah transformasi bukan peak RSS.

Varian dibuat saat diminta, tanpa cache/persistensi R2 baru. Jadi tidak menambah
objek turunan yang perlu retensi, tetapi setiap request masih membaca sumber penuh
dari R2 dan memakai CPU transformasi. Penghematan saat ini pada transfer ke Flutter;
**belum ada penghematan byte storage/R2 egress**. Cache varian persisten memerlukan
metadata/versioning/referensi dan anggaran storage tersendiri.

Pembacaan tetap dibuffer sampai hash tervalidasi. Streaming langsung ke klien dapat
mengirim byte yang kemudian diketahui tidak cocok. Alternatif spool ke disk lalu
stream perlu protokol file sementara, kuota dan retensi yang diuji terlebih dahulu.
Tahap ini mempertahankan verifikasi integritas sebelum respons.

## Profil sintetis

Setelah build, dari `apps/api`: `node scripts/profile-images.cjs`. Skrip memakai
empat fixture acceptance AI sintetis dan menulis hasil/varian ke
`.tmp/performance/images/`, di luar Git. Tidak menghubungi AI atau storage eksternal.

| Fixture | Byte sumber | Byte preview | Byte thumbnail |
| --- | ---: | ---: | ---: |
| truck | 45.619 | 10.342 | 8.204 |
| production | 31.025 | 8.024 | 2.938 |
| manual | 17.230 | 5.030 | 4.624 |
| update | 31.514 | 7.950 | 2.936 |
| Total | 125.388 | 31.346 | 18.702 |

Keempat fixture tidak perlu resize untuk preview; byte piksel hasil decode preview
identik dengan sumber. Transfer preview turun sekitar 75% pada fixture ini. Angka
dan tanggal pada preview truck juga diperiksa secara visual. Thumbnail hanya untuk
daftar, bukan dasar pengesahan angka. Durasi satu putaran lokal preview 110–293 ms,
thumbnail 67–86 ms, RSS sesudah operasi 72–100 MB; ini bukan HTTP p95, peak RAM,
latensi perangkat atau bukti kualitas tulisan tangan/foto buram di lapangan.

## Dedup dan tindak lanjut

Jalur WhatsApp sudah memiliki pencarian hash per pabrik serta alias submission untuk
foto identik. Jangan menyamakan hash identik dengan transaksi/nota bisnis identik.
Evidence penerimaan mempunyai key per lampiran/revisi dan SHA tersendiri; mengganti
fisik penyimpanannya dengan satu objek bersama memerlukan referensi semua pemilik,
isolasi tenant/pabrik, koordinasi upload dan retensi yang aman. Tidak ada dedup lintas
tenant atau perubahan aturan duplikat bisnis pada tahap ini.

Masih perlu pengujian tulisan tangan sintetis, angka kecil pada sumber >2048 piksel,
foto buram/terpotong, latensi perangkat/jaringan dan beban gabungan OCR/review.
Metadata turunan persisten dan peak RAM belum selesai. Kebijakan masa simpan bukti
tetap terbuka; tidak menjadi prasyarat menyajikan preview sementara ini.

Deploy API sebelum Flutter agar parameter preview tersedia. Rollback kedua komponen
tidak memerlukan perubahan database/storage. Decoder lebih ketat dapat menolak
berkas lama yang hanya memiliki header valid; UI tetap menyediakan jalur sumber
asli, dengan pemeriksaan hash/ukuran yang sama.
