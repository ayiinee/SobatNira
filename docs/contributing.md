# Panduan kontribusi SobatNira

Gunakan panduan ini saat menambah fitur, memperbaiki bug, atau mengubah dokumentasi. Langkah instalasi dan perintah tes ada di [panduan setup lokal](development.md).

## Acuan keputusan dan kontrak

- Gunakan [acuan proyek](project-overview.md) untuk memahami domain dan status implementasi. Jika acuan internal tersedia di `docs/internal/`, buka indeks dan periksa status aturan di register keputusan sebelum mengubah perilaku produk. Jika aturan masih terbuka, bertentangan, atau sumbernya belum tersedia, konfirmasi dengan pemilik keputusan dan catat hasilnya di register internal.
- Sepakati perubahan field, status, satuan, atau bentuk error dengan pemilik layanan pengirim dan penerima. Catat perubahan kontrak serta urutan penggabungan jika pekerjaan terbagi di beberapa PR. Gunakan fixture sintetis untuk memeriksa contoh sukses dan gagal pada alur yang terdampak.

## Struktur folder dan penamaan

| Lokasi | Aturan |
| --- | --- |
| `apps/mobile/lib/` | Letakkan layar, widget, dan logika khusus fitur di `features/<fitur>/` saat fitur bertambah. Pertahankan `main.dart` sebagai titik masuk. Untuk file Dart, gunakan `snake_case`, misalnya `kloter_detail_page.dart`. |
| `apps/mobile/test/` | Simpan tes Flutter dengan akhiran `_test.dart`. Untuk tes fitur, ikuti susunan fitur di `lib/` agar file mudah ditemukan. |
| `apps/api/src/` | Kelompokkan controller, service, dan DTO berdasarkan domain, misalnya `documents/` dan `batches/`. Gunakan nama seperti `documents.module.ts`, `documents.controller.ts`, dan `documents.service.ts`. |
| `apps/api/test/` | Simpan tes API di sini. Ikuti pola `*.test.cjs` untuk tes yang dijalankan oleh skrip `npm test` saat ini. |
| `apps/ai/` | Pertahankan `main.py` sebagai titik masuk FastAPI. Saat tanggung jawab bertambah, kelompokkan menurut fungsi, misalnya `ocr/` atau `parsing/`. Gunakan `snake_case` untuk modul Python dan `test_*.py` untuk tes. |
| `docs/` | Simpan panduan teknis yang bisa dibagikan. Simpan spesifikasi dan keputusan internal di `docs/internal/`, yang sudah dikecualikan dari Git. |

Buat folder saat ada kode yang memerlukannya. Ikuti istilah produk yang sudah dipakai pada fitur terkait.

Contoh struktur dari repo saat ini.

```text
SobatNira/
├── apps/
│   ├── mobile/
│   │   ├── assets/sobatnira/
│   │   ├── lib/
│   │   │   ├── features/kloter/
│   │   │   ├── main.dart
│   │   │   └── sobatnira_ui.dart
│   │   ├── test/
│   │   │   ├── features/kloter/
│   │   │   └── support/
│   │   └── pubspec.yaml
│   ├── api/
│   │   ├── src/
│   │   └── test/
│   └── ai/
│       ├── main.py
│       └── test_main.py
├── docs/
└── .github/workflows/ci.yml
```

### Kode bersama

- Simpan widget, helper, dan state Flutter di folder fitur yang memakainya. Pindahkan kode ke lokasi bersama saat beberapa fitur menggunakannya untuk tujuan yang sama. Contoh yang sudah ada adalah komponen UI di [`sobatnira_ui.dart`](../apps/mobile/lib/sobatnira_ui.dart) dan helper login demo di [`test/support/`](../apps/mobile/test/support/).

### Aset dan fixture

- Simpan aset Flutter di `apps/mobile/assets/sobatnira/`. Gunakan `art/` untuk gambar dan ilustrasi, `icons/` untuk ikon, serta `fonts/` untuk font dan lisensinya.
- Periksa [`apps/mobile/pubspec.yaml`](../apps/mobile/pubspec.yaml) saat menambah aset. File langsung di `art/` atau `icons/` sudah tercakup oleh entri direktorinya. Daftarkan direktori baru atau subfolder aset di `flutter.assets`, dan daftarkan keluarga serta bobot font di `flutter.fonts`.
- Simpan data demo sintetis di dekat fitur pemiliknya, seperti [`demo_production.dart`](../apps/mobile/lib/features/kloter/demo_production.dart) pada fitur Kloter. Untuk data yang khusus dipakai tes, letakkan bersama tes yang memakainya. Simpan fixture yang dipakai beberapa tes di lokasi pendukung dalam area tes aplikasi tersebut.

## Nama branch dan commit

Mulai dari `main` terbaru. Gunakan pola `<jenis>/<area>-<ringkasan>` dengan huruf kecil dan tanda hubung. Awali nama branch langsung dengan jenis pekerjaan, seperti `feat/`, `fix/`, `docs/`, atau `test/`. Pakai area seperti `mobile`, `api`, `ai`, atau `repo`. Jika ada issue, nomornya boleh ditambahkan.

```text
feat/mobile-kloter-detail
fix/api-42-validasi-dokumen
docs/repo-panduan-kontribusi
test/ai-fixture-ekstraksi
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

- [Workflow CI](../.github/workflows/ci.yml) berjalan saat ada pull request ke `main` dan saat ada push ke `main`. CI menjalankan analisis dan tes Flutter, build dan tes NestJS, serta unit test FastAPI. Periksa hasilnya pada PR sebelum merge.
- Jalankan pemeriksaan komponen terkait dari [panduan setup](development.md#tes-sebelum-mengambil-tugas). Untuk perubahan antar layanan, cek alur dari aplikasi hingga API yang terdampak. Jika mengubah perilaku khusus Android, uji pada emulator atau HP dan sebutkan perangkat yang dipakai.
- Saat kontrak berubah, perbarui fixture dan pemanggil terkait.
- Perbarui lockfile komponen saat dependensi berubah. Gunakan fixture sintetis dan contoh konfigurasi tanpa rahasia. Periksa perubahan yang akan masuk Git agar kredensial, data mitra, cache, dan hasil build tetap tersimpan lokal.
- Jika lokasi bisa dipilih di Windows dan drive D: tersedia, gunakan D: untuk workspace, cache, file sementara, emulator, dan hasil build.

## Saran saat pekerjaan tim bertambah

- Saat database mulai dipakai, simpan perubahan skema sebagai migrasi berversi. Uji pada database lokal atau lingkungan development dengan data sintetis, lalu dokumentasikan urutan penerapannya sebelum menggabungkan perubahan.
