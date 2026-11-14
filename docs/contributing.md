# Panduan kontribusi SobatNira

Gunakan panduan ini saat menambah fitur, memperbaiki bug, atau mengubah dokumentasi. Langkah instalasi dan perintah tes ada di [panduan setup lokal](development.md).

## Struktur folder dan penamaan

| Lokasi | Aturan |
| --- | --- |
| `apps/mobile/lib/` | Letakkan layar, widget, dan logika khusus fitur di `features/<fitur>/` saat fitur bertambah. Pertahankan `main.dart` sebagai titik masuk. Untuk file Dart, gunakan `snake_case`, misalnya `kloter_detail_page.dart`. |
| `apps/mobile/test/` | Simpan tes Flutter dengan akhiran `_test.dart`. Untuk tes fitur, ikuti susunan fitur di `lib/` agar file mudah ditemukan. |
| `apps/api/src/` | Kelompokkan controller, service, dan DTO berdasarkan domain, misalnya `documents/` dan `batches/`. Gunakan nama seperti `documents.module.ts`, `documents.controller.ts`, dan `documents.service.ts`. |
| `apps/api/test/` | Simpan tes API di sini. Ikuti pola `*.test.cjs` untuk tes yang dijalankan oleh skrip `npm test` saat ini. |
| `apps/ai/` | Pertahankan `main.py` sebagai titik masuk FastAPI. Saat tanggung jawab bertambah, kelompokkan menurut fungsi, misalnya `ocr/` atau `parsing/`. Gunakan `snake_case` untuk modul Python dan `test_*.py` untuk tes. |
| `docs/` | Simpan panduan teknis yang bisa dibagikan. Simpan spesifikasi dan keputusan internal di `docs/internal/`, yang sudah dikecualikan dari Git. |

Buat folder saat ada kode yang memerlukannya. Taruh komponen dan helper di dekat fitur pemiliknya. Pindahkan ke lokasi bersama ketika ada penggunaan bersama dengan tanggung jawab yang jelas. Ikuti istilah produk yang sudah dipakai pada fitur terkait.

## Nama branch dan commit

Mulai dari `main` terbaru. Gunakan pola `<jenis>/<area>-<ringkasan>` dengan huruf kecil dan tanda hubung. Pakai area seperti `mobile`, `api`, `ai`, atau `repo`. Jika ada issue, nomornya boleh ditambahkan. Untuk branch yang dibuat Codex, awali dengan `codex/`.

```text
feat/mobile-kloter-detail
fix/api-42-validasi-dokumen
docs/repo-panduan-kontribusi
codex/test/ai-fixture-ekstraksi
```

Buat satu perubahan yang utuh per commit. Pakai format Conventional Commits `<jenis>(<area>): <ringkasan>` dengan kata kerja yang menjelaskan perubahan. Jenis umum: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, dan `ci`. Jika perubahan memutus kompatibilitas kontrak, tandai dengan `!` dan jelaskan dampaknya di PR.

```text
feat(mobile): add kloter detail page
fix(api): reject invalid document status
test(ai): cover synthetic extraction fixture
docs(repo): document contribution workflow
```

[Spesifikasi Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

## Alur kerja dan pull request

1. Sepakati tujuan tugas dan kondisi yang menunjukkan pekerjaan selesai. Tautkan issue jika ada. Untuk aturan produksi yang masih terbuka, konfirmasi dengan pemilik keputusan sebelum memasukkannya ke kode.
2. Buat branch dari `main`, kerjakan satu lingkup tugas, dan buka PR ke `main`. Gunakan draft PR jika tim perlu melihat perubahan sebelum siap direview.
3. Jelaskan perilaku yang berubah, cara memeriksanya, dan hasil tes di deskripsi PR. Untuk perubahan layar, sertakan tangkapan layar bila membantu reviewer. Tandai pemeriksaan yang belum bisa dijalankan.
4. Minta review pemilik area. Jika perubahan memengaruhi Flutter, NestJS, atau FastAPI melalui kontrak bersama, libatkan pemilik layanan yang mengirim dan yang menerima data.
5. Gabungkan setelah komentar yang menghalangi merge selesai dan pemeriksaan terkait lulus. Gunakan squash merge bila tersedia dan pertahankan format judul commit pada hasil merge.

[GitHub Flow](https://docs.github.com/en/get-started/using-github/github-flow).

## Verifikasi dan pengelolaan perubahan

- Jalankan pemeriksaan komponen terkait dari [panduan setup](development.md#tes-sebelum-mengambil-tugas). Untuk perubahan antar layanan, cek alur dari aplikasi hingga API yang terdampak. Jika mengubah perilaku khusus Android, uji pada emulator atau HP dan sebutkan perangkat yang dipakai.
- Saat kontrak berubah, catat field, status, atau bentuk error yang berubah. Perbarui fixture dan pemanggil terkait. Koordinasikan urutan merge jika perubahan backend dan klien masuk lewat PR berbeda.
- Perbarui lockfile komponen saat dependensi berubah. Gunakan fixture sintetis dan contoh konfigurasi tanpa rahasia. Periksa perubahan yang akan masuk Git agar kredensial, data mitra, cache, dan hasil build tetap tersimpan lokal.
- Jika lokasi bisa dipilih di Windows dan drive D: tersedia, gunakan D: untuk workspace, cache, file sementara, emulator, dan hasil build.

## Saran saat pekerjaan tim bertambah

- Tambahkan CI yang menjalankan pemeriksaan dari panduan setup ketika PR mulai rutin masuk. Pakai pemeriksaan yang sudah stabil sebagai syarat merge setelah tim menyepakatinya.
- Saat database mulai dipakai, simpan perubahan skema sebagai migrasi berversi. Uji pada database lokal atau lingkungan development dengan data sintetis, lalu dokumentasikan urutan penerapannya sebelum menggabungkan perubahan.
