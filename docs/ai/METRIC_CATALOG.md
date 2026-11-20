# Katalog metrik resmi

| Metrik | Satuan | Definisi dan sumber |
| --- | --- | --- |
| Tebu diterima | kg | Jumlah berat bersih dari penerimaan sah per kloter yang masuk periode. Gunakan hasil rekonsiliasi yang dipakai query resmi. |
| Nira dihasilkan | L | Volume yang disahkan pada penggilingan, termasuk rekonsiliasi resmi. |
| Nira dikonsumsi dan asal | mL | Debit persediaan dari `juice_reservations` berstatus `consumed` pada batch sah. Asal dan kloter penyimpan memakai ID ledger. |
| Kontribusi nira terbesar pada basis eksplisit | mL | Jumlah eksak debit menurut kloter asal, meliputi batch sah pada kloter yang diterima dalam periode laporan. Selisih antara volume batch sah dan debit ledger menahan peringkat. Semua pemenang seri dihitung, hingga sepuluh ditampilkan. |
| Berat fisik dan gula final | kg | Berat fisik tersimpan pada batch. Gula final adalah berat hasil grade yang sah pada snapshot. |
| Distribusi grade | kg dan Rp | Agregat berat grade sah. Nilai grade mempertahankan perkalian eksak berat dan harga tersimpan. |
| Rendemen | % | Hasil gula final dibagi berat tebu bersih pada kloter, dikali 100, mengikuti presisi kalkulator NestJS. Agregat lintas kloter tidak ditambahkan sebagai rumus baru. |
| Nilai produksi | Rp | Total nilai grade dari snapshot, memakai pembulatan resmi kalkulator. |
| Total biaya | Rp | Tebu, operasional, bahan dan biaya lain dari snapshot. |
| Margin produksi | Rp | Nilai produksi dikurangi total biaya pada snapshot yang sama. Margin pada kloter terbuka bersifat sementara. |
| Perbandingan periode | Sesuai metrik | Dua jendela inklusif awal dan eksklusif akhir menggunakan tanggal penerimaan kloter. Keduanya memakai satu pembacaan PostgreSQL. |

API menerima periode ISO 8601 dengan zona waktu dan menyaring data pabrik serta pilihan sintetis. Rounding dan presisi berasal dari `production/calculation.ts` dan `production/decimal.ts`. Owner membaca capability. Cakupan pembacaan Laporan Flutter yang ada tercatat dalam [register keputusan](DECISIONS_REQUIRED.md).
