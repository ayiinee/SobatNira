# Daftar penyambungan card informasi ke backend

Pemeriksaan kode: 19 November 2026. Dokumen ini memetakan jalur antarmuka utama saat ini, bukan hasil pengujian API/database live. Tidak mengubah implementasi.

## Status card

| Halaman | Card / angka | Sumber saat ini | Pekerjaan integrasi |
| --- | --- | --- | --- |
| Beranda | Keuntungan | Mode demo: literal Rp15.745.000; connected: Belum tersedia | Ambil agregat margin/keuntungan yang definisinya disepakati dan sesuai pabrik/periode |
| Beranda | Tebu diterima | Demo: literal 8.200Kg; connected: jumlah netWeightKg dari daftar kloter API | Sudah sebagian; perlu definisi periode dan status penerimaan, serta agregat resmi agar tidak bergantung pada isi daftar |
| Beranda | Jumlah kloter | Demo: literal 3; connected: jumlah kloter yang dimuat dari API | Sudah sebagian; tentukan semua kloter atau kloter pada periode/status tertentu; samakan dengan card tebu |
| Laporan / Produksi | Gula final | Demo: DemoAnalytics.sugarTotal dari fixture; connected: Belum tersedia | Agregat hasil gula final yang sah, dengan penanganan grade/rework sesuai aturan |
| Laporan / Produksi | Tebu diterima | Demo: DemoAnalytics.caneTotal; connected: jumlah berat kloter API yang lolos filter tanggal lokal | Sudah sebagian; sinkronkan agregat dengan periode dan definisi backend |
| Laporan / Margin | Margin Produksi | Demo: DemoAnalytics.marginTotal; connected: Belum tersedia | Sambungkan ringkasan margin resmi |
| Laporan / Margin | Nilai produksi | Demo: nilai produksi dari fixture/harga demo; jalur connected belum menampilkan card ini | Jumlah berat grade sah x harga snapshot, sesuai kontrak backend |
| Laporan / Margin | Total biaya | Demo: nilai produksi dikurangi margin fixture; jalur connected belum menampilkan card ini | Ambil biaya aktual/snapshot yang dicakup, bukan menghitung balik dari angka demo |
| Pintasan Laba | Total margin kloter | Jalur utama memakai fromApprovedLots dengan rows kosong, sehingga total connected '-' | Arahkan ke adapter laporan laba yang sudah tersedia atau berikan snapshot hasil API ke ReportExportPage |
| Pintasan Rekap | Total gula final | Demo: penjumlahan AnalyticsRow; connected: '-' | Gabungkan hasil backend berdasarkan UUID kloter |
| Pintasan Rekap | Margin tercatat | Demo: penjumlahan margin fixture; connected: '-' | Gunakan margin sah per kloter dan total dengan periode identik |
| Pintasan Rekap | Jumlah batch / cakupan data | Demo: jumlah batch dalam model demo; connected: rincian batch belum tersedia | Hubungkan batch dan statusnya ke kloter; bedakan belum tersedia dengan nol |
| Detail Grade | Nilai produksi | gradeTotal x harga demo A/B/C 20.000/18.000/15.000 | Hubungkan berat final per grade dan harga historis yang dibekukan |
| Detail Rendemen / Margin kloter | Identitas kloter pada card hijau, gula/rendemen/margin terkait | ReportDetailPage memakai DemoLotFixture | Detail berdasarkan UUID kloter dari API, bukan lookup fixture dari kode tampilan |
| Detail batch | Margin Produksi (baris informasi, bukan card hijau tersendiri) | Literal Rp670.000 | Sambungkan perhitungan ekonomi batch; jangan memakai literal |

Card detail kloter untuk tebu/Brix/nira dan stok nira sudah mempunyai jalur connected ke API. Ini berbeda dari detail laporan yang masih memakai fixture. Jangan mengganti semua angka sekaligus tanpa membedakan kedua jalur tersebut.

## Bukti lokasi kode

- `apps/mobile/lib/features/beranda/beranda_page.dart`: `_ProductionSummary`, literal keuntungan dan fallback card.
- `apps/mobile/lib/main.dart`: `_summary()` menjumlah berat/jumlah kloter; `_pageFor()` memilih Laporan connected; `_openQuickAction()` membuka Laba/Rekap melalui ReportExportPage.
- `apps/mobile/lib/features/kloter/connected_production.dart`: memuat seluruh halaman kloter API dengan includeSummary, bukan sekadar satu halaman.
- `apps/mobile/lib/features/laporan/laporan_page.dart`: `_connectedReport()`, `_production()`, `_margin()`.
- `apps/mobile/lib/features/laporan/demo_analytics.dart` dan `../kloter/demo_lot_fixture.dart`: sumber jumlah/nilai ilustratif.
- `apps/mobile/lib/features/laporan/printable_report.dart`: `fromAnalytics()` vs `fromApprovedLots()`; versi approved membuat rows kosong dan belum menyuplai hasil produksi/ekonomi.
- `apps/mobile/lib/features/laporan/production_recap.dart`: `fromApprovedLots()` mengisi sugar/rendemen '-', margin null dan batches kosong secara eksplisit.
- `apps/mobile/lib/features/laporan/report_detail_page.dart`: detail grade/rendemen/margin memakai fixture.
- `apps/mobile/lib/features/kloter/batch_detail_page.dart`: literal margin batch.

## Backend/adapter yang sudah tersedia: pakai kembali dahulu

1. Endpoint scoped `GET /tenants/:tenantId/factories/:factoryId/production/profit-report` sudah tersedia, beserta `ReviewApi.profitReport()` dan `ConnectedProfitPage`. Jalur utama Beranda saat ini tidak memakai ConnectedProfitPage; pemanggilannya ada di halaman connected lama. Ini pekerjaan routing/adaptasi frontend, bukan alasan membuat kalkulator laba baru.
2. Endpoint `GET /dashboard/production`, `/analytics/production` dan `/exports/batches.csv` sudah tersedia dari modul reporting. Ada ProductionDashboardPage terpisah dari halaman utama. Adapter dashboard tersebut masih memakai header identitas development dan fallback fixture ketika API_BASE_URL kosong. Jangan menganggap adapter ini sudah siap untuk sesi Supabase produksi.
3. Dashboard reporting mempunyai total batch, nira dan hasil gula, tetapi belum otomatis menyediakan seluruh card biaya, tebu dan margin. Periksa pula definisi status resmi dan rework sebelum memakai total sebagai angka final.
4. Endpoint perhitungan `calculation-preview`/`recap-preview` hanya simulasi input. Hasilnya tidak boleh menjadi pengganti pembacaan transaksi yang sudah sah.

## Checklist untuk teman backend/frontend

- Pilih satu jalur API dengan Bearer Supabase, tenant dan factory yang aktif. Repo mempunyai dua jalur modul batch; cocokkan sumber tabel/layanan agar angka tidak tercampur.
- Tetapkan filter yang sama: awal periode, akhir eksklusif, zona waktu pabrik, status transaksi, dan synthetic/riil. Default semua tanggal berbeda dengan hari ini.
- Agregat harus meliputi seluruh data yang memenuhi filter, bukan hanya lima baris pagination yang terlihat.
- Gunakan penerimaan/hasil/biaya yang sah. Tentukan perlakuan koreksi, pembatalan, rework dan batch campuran agar tidak dihitung dua kali.
- Nilai produksi memakai harga snapshot transaksi, bukan harga Setting terbaru. Total biaya memerlukan komponen/basis pembebanan yang jelas.
- Sepakati apakah Keuntungan di Beranda sama dengan margin produksi atau mempunyai cakupan lain. Jangan menamai margin sebagai laba bersih tanpa definisi yang sesuai.
- Jaga satuan: kg untuk tebu/gula, liter atau ml untuk nira, rupiah untuk nilai/biaya, persen untuk rendemen. Brix bukan rendemen.
- Nilai yang benar-benar nol harus tampil 0; nilai yang belum tersedia tampil null/Belum tersedia, dan kegagalan pemuatan punya status sendiri.
- UI, grafik, rincian, PDF dan CSV memakai agregasi/filter yang sama. Pagination tidak boleh mengubah card total atau jumlah data yang dicetak.
- Setelah validasi/koreksi batch atau pergantian pabrik/periode, muat ulang seluruh ringkasan terkait.

### Bentuk respons gabungan yang dapat disepakati (usulan, belum kontrak aktif)

```json
{
  "factoryId": "uuid",
  "period": {"from": "ISO8601", "before": "ISO8601", "timezone": "Asia/Jakarta"},
  "synthetic": false,
  "totals": {
    "lotCount": 0,
    "batchCount": 0,
    "caneNetKg": "0",
    "finalSugarKg": null,
    "productionValueRupiah": null,
    "totalCostRupiah": null,
    "productionMarginRupiah": null,
    "rendemenPercent": null
  },
  "coverage": {"lotsWithFinalSugar": 0, "lotsWithCosts": 0}
}
```

Gunakan string untuk nilai eksak. Endpoint gabungan baru hanya diperlukan bila endpoint yang ada tidak dapat memasok kontrak tersebut; nama rute dan field final perlu disepakati.

## Urutan prioritas

1. Sambungkan profit-report ke pintasan Laba, lalu ringkasan keuntungan Beranda dengan periode yang disepakati.
2. Sambungkan gula final, nilai produksi, biaya dan margin di Laporan utama; rapikan definisi total tebu/jumlah kloter.
3. Sambungkan snapshot Rekap beserta rincian batch, kemudian Detail Grade/Rendemen/Margin.
4. Verifikasi angka UI = jumlah rincian seluruh halaman = PDF = hasil query backend untuk filter yang sama. Uji nol data, rugi, data belum lengkap, perubahan harga historis dan koreksi validasi.
