import { BadRequestException } from '@nestjs/common';
export const REPORT_MAX_LOTS = 100;
export const REPORT_MAX_BYTES = 5 * 1024 * 1024;
export function reportPeriod(from: string | null, before: string | null) {
  if (from && before && (from >= before || Date.parse(before) - Date.parse(from) > 366 * 86400000)) {
    throw new BadRequestException('Periode laporan maksimum 366 hari. Persempit periode laporan.');
  }
}
export function boundedReport<T>(report: T): T {
  if (Buffer.byteLength(JSON.stringify(report)) > REPORT_MAX_BYTES) {
    throw new BadRequestException('Laporan melebihi 5 MiB. Persempit periode atau gunakan ekspor laporan asinkron.');
  }
  return report;
}
