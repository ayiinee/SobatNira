import { Workbook } from 'exceljs';
import { PDFDocument, StandardFonts } from 'pdf-lib';
import { Batches } from './batches';

export type ReportSnapshot = Awaited<ReturnType<Batches['productionReport']>>;
export type ReportFormat = 'pdf' | 'xlsx';
export const formats: ReportFormat[] = ['pdf', 'xlsx'];

export const reportMime = {
  pdf: 'application/pdf',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
};

function tables(snapshot: ReportSnapshot) {
  const totals = snapshot.totals;
  return {
    Ringkasan: [
      ['Dari (inklusif)', snapshot.from ?? ''],
      ['Sebelum (eksklusif)', snapshot.before ?? ''],
      ['Basis periode', snapshot.periodBasis],
      ['Data contoh', snapshot.synthetic ? 'Ya' : 'Tidak'],
      ['Kloter', String(totals.lotCount)],
      ['Batch sah', String(totals.batchCount)],
      ['Tebu bersih (kg)', totals.caneNetKg],
      ['Gula final (kg)', totals.finalSugarKg],
      ['Nilai produksi (Rp)', totals.productionValueRupiah],
      ['Total biaya (Rp)', totals.totalCostRupiah],
      ['Margin produksi (Rp)', totals.productionMarginRupiah],
      ['Catatan', 'Margin bersifat sementara untuk kloter terbuka.'],
    ],
    Grade: [['Kode grade', 'Gula final (kg)', 'Nilai eksak (Rp)'],
      ...snapshot.grades.map(row => [row.code, row.weightKg, row.exactValueRupiah])],
    Kloter: [['ID kloter', 'Kode', 'ID snapshot', 'Gula final (kg)', 'Biaya (Rp)', 'Margin (Rp)'],
      ...snapshot.items.map(lot => [lot.lotId, lot.code, lot.calculationSnapshotId ?? '',
        lot.calculation?.finalSugarKg ?? '', lot.calculation?.totalCostRupiah ?? '',
        lot.calculation?.productionMarginRupiah ?? ''])],
  };
}

export async function renderReport(format: ReportFormat, snapshot: ReportSnapshot, createdAt: Date) {
  const rows = tables(snapshot);
  if (format === 'xlsx') {
    const workbook = new Workbook();
    workbook.creator = 'SobatNira';
    workbook.created = createdAt;
    workbook.modified = createdAt;
    for (const [name, values] of Object.entries(rows)) {
      const sheet = workbook.addWorksheet(name);
      sheet.addRows(values);
      for (const column of sheet.columns) column.width = 30;
    }
    return Buffer.from(await workbook.xlsx.writeBuffer());
  }
  const pdf = await PDFDocument.create({ updateMetadata: false });
  pdf.setTitle('SobatNira - Rekap produksi');
  pdf.setCreationDate(createdAt);
  pdf.setModificationDate(createdAt);
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  let page = pdf.addPage([842, 595]);
  let y = 550;
  const line = (value: string, size = 10) => {
    // The PDF uses a standard font. The Excel artifact retains the full stored text.
    const text = value.replace(/[^\x20-\x7e]/g, '?').replace(/\s+/g, ' ');
    if (y < 35) { page = pdf.addPage([842, 595]); y = 550; }
    page.drawText(text, { x: 30, y, size, font, maxWidth: 782, lineHeight: 12 });
    y -= Math.max(1, Math.ceil(font.widthOfTextAtSize(text, size) / 710)) * 12 + 4;
  };
  line('SobatNira - Rekap produksi', 16);
  for (const [name, values] of Object.entries(rows)) {
    line(name, 13);
    for (const value of values) line(value.join(' | '));
  }
  return Buffer.from(await pdf.save());
}

export async function verifyReport(format: ReportFormat, bytes: Buffer, expected: Buffer, snapshot: ReportSnapshot) {
  if (bytes.equals(expected)) return;
  if (format !== 'xlsx') throw new Error('PDF tersimpan berbeda dari snapshot.');
  // Excel ZIP metadata can change between attempts, so compare its cell values.
  const workbook = new Workbook();
  await workbook.xlsx.load(bytes as unknown as Parameters<typeof workbook.xlsx.load>[0]);
  for (const [name, values] of Object.entries(tables(snapshot))) {
    const sheet = workbook.getWorksheet(name);
    if (!sheet || sheet.rowCount !== values.length || values.some((row, i) =>
      row.some((value, j) => sheet.getCell(i + 1, j + 1).value !== value))) {
      throw new Error('Isi XLSX tersimpan berbeda dari snapshot.');
    }
  }
}
