# Peta domain dan sumber resmi

| Domain | Rute atau entry point | Sumber dan konsumen |
| --- | --- | --- |
| WhatsApp, OCR dan review | OpenClaw `reply_dispatch`, `/internal/v1/whatsapp/*`, FastAPI `/internal/v1/ocr/extract`, Flutter Pekerjaan | `whatsapp_inbound_messages`, `media_assets`, `document_submissions`, `document_jobs`, `extraction_attempts`, `document_revisions`, `operator_confirmations`, `admin_review_tasks`, `document_approvals`, `whatsapp_notices`. OCR menghasilkan draf. PostgreSQL mencatat pengesahan dan referensinya. |
| Penerimaan dan penggilingan | Flutter Kloter dan `/tenants/:tenantId/factories/:factoryId/lots` | `sobatnira.lots`, `intake_records`, `milling_records`, `stock_reconciliations`. Dokumen sumber mengacu ke revisi sah. |
| Persediaan nira | `juice/availability`, `juice/reservations`, transfer dan penutupan per kloter | `juice_stock_movements`, `juice_transfers`, `juice_reservations`, `juice_balance_entries`. Debit konsumsi dan asal kontribusi mengikuti ledger. |
| Batch dan ekonomi | `production/batches`, `production/lots/:id/costs` | `production_batches`, `batch_grade_results`, `lot_production_costs`, `production_calculation_snapshots`. NestJS membekukan nilai input dan hasil setelah sah. |
| Laporan | Flutter `review_api.dart`, `production-report`, `profit-report`, `recap`, `capabilities/query` | Laporan dan capability memakai snapshot kalkulasi terakhir per kloter. PDF Flutter dan ekspor owner mengikuti angka resmi yang sama. Insight gabungan membaca total, grade, dan debit `juice_reservations` per kloter asal dalam satu statement ketika dasar peringkat disebut. |
| Jalur B1 historis | `/dashboard/production`, `/analytics/production`, `/exports/batches.csv`, `/production-masters/*`, `/batches/:id/reworks` | `ReportingService` dan `BatchesService` memiliki model lama serta adapter memori/Supabase. Penelusuran repo menemukan caller langsung ketiga rute laporan lama di `b1-batches.test.cjs`. Flutter terhubung memakai rute pabrik pada baris di atas. Konsumen di luar repo masih perlu dikonfirmasi. |

Scope transaksi resmi mengikuti tenant, pabrik, dan membership aktif. API capability mengharuskan owner. Akses laporan Flutter lama dan pengaturan master mengikuti [register keputusan](DECISIONS_REQUIRED.md). Rework lama tidak diasumsikan terhubung dengan ID batch resmi.
