# Evaluasi POC-01 Production Insight

## Hasil

Rekomendasi **no-go untuk adopsi saat ini**. Langflow Base 1.13.3 berjalan di environment Python terisolasi dan memberi hasil sama dengan tiga query native yang memakai NestJS dan PostgreSQL. Seluruh 5 putaran menghasilkan 25 kg gula grade A, Rp375.000 margin, 40.000 mL kontribusi, dan sumber yang sama. Jalur native memenuhi kebutuhan POC dengan latensi median lebih rendah.

Setelah sesi owner dan ekspor native diintegrasikan, keputusan no-go tetap berlaku. Pengukuran di bawah berasal dari POC REST lama dengan tiga operasi baca. Harness terbaru memakai satu `get_production_insight` untuk produksi, grade, dan peringkat kontribusi nira, dengan basis tanggal penerimaan kloter batch yang eksplisit. Verifikasi kontrak terbaru memakai stub REST. Runtime Langflow dengan kontrak baru, pairing, dan ekspor persisten belum diukur. [Laporan E2E](E2E_TEST_REPORT.md)

| Pemeriksaan | Hasil |
| --- | --- |
| Runtime | `/docs` merespons 200. OpenAPI versi `1.13.3` memuat `POST /api/v1/run/{flow_id_or_name}`. |
| Latensi lokal | Median 5 bacaan native **26 ms** dan REST Langflow **123 ms**. Putaran pertama 224 ms dan 1.212 ms. Empat putaran berikutnya native 25–31 ms dan REST 117–147 ms. Sampel kecil dan belum ada p95. |
| Autentikasi | Auto-login dan request eksekusi tanpa API key ditolak dengan `403`. Gateway menolak secret kosong. Token admin yang diteruskan gateway gagal di NestJS, dan putusnya gateway membuat eksekusi gagal. |
| Dependensi | Paket base menyiapkan 331 paket di environment sementara. Cache offline awal kosong dan percobaan online pertama timeout. Percobaan ulang dengan waktu unduh lebih longgar berhasil. Dependensi aplikasi tidak diubah. |
| Biaya dan resource | Flow deterministik tanpa panggilan inference provider. Latensi terukur. Penggunaan RAM, kapasitas, atau biaya operasional bulanan belum diukur. |

Tes REST stub juga lulus untuk perbedaan angka yang sengaja dimasukkan, API key keliru, dan scope tambahan pada gateway. Saat startup awal, Langflow mengambil katalog model publik. Putaran berikutnya memakai proxy lokal buntu untuk akses HTTP keluar, dengan loopback dikecualikan. Uji menggunakan data sintetis. Untuk deployment berikutnya, isolasikan jaringan dan kontrol egress pada runtime.

## Menjalankan fixture

1. Selesaikan [acceptance lokal](README.md) sampai kloter `OCR-A-UJI` punya batch sah. Siapkan token owner dari server login sintetis serta UUID tenant dan pabrik fixture. Jalankan `node --test tools/langflow-poc/production-insight.test.mjs` untuk uji kontrak tanpa Langflow.
2. Pada environment Python terpisah dengan ruang cukup, pasang `langflow-base==1.13.3`. Jalankan dengan bind `127.0.0.1:7860`, `LANGFLOW_AUTO_LOGIN=false`, `LANGFLOW_AGENTIC_EXPERIENCE=false`, kredensial lokal unik, dan `LANGFLOW_SECRET_KEY` format Fernet dari `Fernet.generate_key()`. Batasi pengguna pada operator POC dan gunakan penyimpanan dev terpisah. Periksa `langflow --version` serta `/docs` di runtime yang dipasang dan pastikan rute REST `POST /api/v1/run/{flow_id}` meminta `x-api-key`. [Dokumentasi instalasi](https://docs.langflow.org/get-started-installation) · [Dokumentasi API](https://docs.langflow.org/api-reference-api-examples) · [Dokumentasi konfigurasi](https://docs.langflow.org/environment-variables)
3. Setel secret acak minimal 32 byte `SOBATNIRA_POC_GATEWAY_SECRET` pada proses Langflow dan gateway. Pada proses gateway saja, setel `POC_TENANT_ID`, `POC_FACTORY_ID`, `POC_OWNER_TOKEN`, `POC_FROM`, dan `POC_BEFORE`. Jalankan `node tools/langflow-poc/production-insight.mjs gateway`. Langflow tidak menerima token SobatNira. Gunakan hanya data sintetis dan simpan secret di luar flow dan Git.
4. Gunakan interpreter environment POC untuk `python tools/langflow-poc/build_flow.py <file-json-di-luar-Git>`. Impor JSON lewat editor atau API create flow. Chat Output disetel tanpa menyimpan pesan. Ambil ID flow dan API key runtime. Jalankan `node tools/langflow-poc/production-insight.mjs compare` dengan variabel scope native yang sama serta `POC_LANGFLOW_ID` dan `POC_LANGFLOW_KEY`. [Dokumentasi impor flow](https://docs.langflow.org/concepts-flows-import) · [Dokumentasi custom component](https://docs.langflow.org/components/custom/)
5. Catat minimal hasil parity, latency native dan REST secara terpisah, hasil tanpa API key, hasil setelah token owner dicabut, kegagalan gateway, serta konsumsi resource. Tutup kedua proses dev setelah uji. Jika kontrak atau kinerja runtime berbeda, gunakan native dan catat selisih sebelum mempertimbangkan POC berikutnya.

Custom component menjalankan Python di proses Langflow. Karantina eksperimen dari kredensial dan data riil, dan batasi author flow secara ketat. [Dokumentasi keamanan custom components](https://docs.langflow.org/deployment-block-custom-components)
