# Komputasi produksi: preview v1

Modul ini menghitung input eksplisit; belum menjadi pembukuan produksi resmi atau laporan yang membaca transaksi Supabase. Tidak mengubah nota, OCR, review, ledger, harga, atau status batch. Pembulatan dan basis rendemen pada kontrak ini harus disepakati sebelum dipakai dalam pengesahan produksi.

Endpoint dengan Bearer token dan membership admin/owner pada tenant/pabrik:

- `POST /tenants/:tenantId/factories/:factoryId/production/calculation-preview`
- `POST /tenants/:tenantId/factories/:factoryId/production/recap-preview`

Body perhitungan:

```json
{
  "caneNetKg": "1500",
  "caneCostRupiah": "900000",
  "operationalCostRupiah": "100000",
  "ingredientCostRupiah": "20000",
  "otherCostRupiah": "0",
  "rounding": "HALF_UP",
  "grades": [
    {"code": "A", "weightKg": "30", "pricePerKgRupiah": "20000"},
    {"code": "B", "weightKg": "30", "pricePerKgRupiah": "18000"},
    {"code": "C", "weightKg": "30", "pricePerKgRupiah": "15000"}
  ]
}
```

Hasil utama: gula final `90` kg, rendemen `6.00` persen, nilai produksi `1590000`, biaya `1020000`, margin `570000` rupiah. Margin dapat negatif. Nilai produksi bukan penjualan atau laba bersih.

Semua angka input/output berupa string. Berat positif maksimal enam desimal kg; biaya/harga integer rupiah nonnegatif maksimal 30 digit. Tidak menerima eksponen, pemisah ribuan, scope palsu, field tidak dikenal atau grade duplikat. Grade 1–100 baris. Algoritme BigInt menghindari floating-point; nilai produksi dibulatkan HALF_UP satu kali setelah penjumlahan nilai grade, bukan per baris. Rendemen dibulatkan HALF_UP ke dua desimal. Satuan nira tidak dikonversi ke kg dan Brix tidak dipakai sebagai rendemen.

Body rekap: `{"records":[{"lotCode":"K1","calculation":{...body di atas...}}]}`. Maksimal 100 kloter, kode unik tanpa membedakan kapital. Total nilai produksi menjumlah nilai yang telah dibulatkan per kloter; rendemen total dihitung dari total berat gula / total tebu, bukan rata-rata persentase kloter. Nilai input tidak menjadi bukti transaksi sah hanya karena pengguna mempunyai akses pabrik.

Respons selalu menyebut `mode: "preview"`, `persisted: false` dan `calculationVersion`. Klien tidak boleh memakai respons ini sebagai pengesahan atau mengubah stok. Harga/biaya historis dan alokasi batch campuran belum dikerjakan di modul ini.

## Fixture sintetis yang dapat diulang

Dari `apps/api`:

```powershell
npm run seed:calculations --silent
```

Menghasilkan JSON dengan tiga skenario (untung, rugi, berat pecahan), asumsi fixture, serta 30 kloter untuk rekap bulanan. Generator deterministik dan tidak membaca `.env`, tidak terhubung database dan tidak menulis Supabase. Ini seed **perhitungan**, bukan seeder entitas/database lengkap. Untuk menyimpan keluaran, arahkan ke file dalam `.tmp` atau lokasi development privat.

Tes: `npm test` mencakup contoh emas, angka di atas batas safe integer JavaScript, pembulatan jumlah, input salah, kloter duplikat, rendemen berbobot dan HTTP dengan autentikasi/cakupan pabrik. Pengujian HTTP memakai identitas sintetis; bukan sesi Supabase nyata.

## Pekerjaan berikutnya

Persistensi master/batch/harga/biaya, snapshot saat validasi, pembatalan yang teraudit, alokasi campuran, endpoint laporan dari transaksi sah, seeder database dan integrasi Flutter masih perlu implementasi terpisah. Terapkan setelah definisi domain dan kepemilikan Backend B disepakati. Jangan menjalankan reset atau seed pada database produksi untuk mencoba preview ini.
