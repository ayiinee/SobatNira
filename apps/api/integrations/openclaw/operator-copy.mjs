const labels = {
  arrival_date: 'Tanggal datang', supplier_name: 'Pengirim', vehicle_number: 'Nomor kendaraan',
  brix: 'Brix', net_weight_kg: 'Berat bersih', cane_type: 'Jenis tebu',
  receiving_operator: 'Operator pada nota', production_date: 'Tanggal produksi',
  shift: 'Sif', chef: 'Petugas masak', cane_label: 'Label tebu', pan_number: 'Wajan',
  isi_kg: 'Isi', gamping: 'Gamping', jam_turun: 'Jam turun', grade: 'Grade', hasil_kg: 'Hasil',
};
const number = new Intl.NumberFormat('id-ID', { maximumFractionDigits: 5 });
const date = new Intl.DateTimeFormat('id-ID', { dateStyle: 'long', timeZone: 'UTC' });
export const terminal = new Set(['EXTRACTED', 'NEEDS_CLARIFICATION', 'MANUAL_REVIEW_REQUIRED', 'FAILED_FINAL']);
export const operatorHelp = 'Halo! Kirim satu foto nota truk atau nota produksi. Ketik STATUS untuk melihat nota terakhir, atau BANTUAN untuk petunjuk.';
export const operatorInstructions = [
  '*Cara pakai SobatNira*',
  '1. Kirim satu foto nota. Untuk nota baru, beri caption BARU.',
  '2. Tunggu ringkasan atau ketik STATUS.',
  '3. Balas ringkasan dengan KONFIRMASI jika datanya sesuai.',
  'Untuk melanjutkan nota produksi, balas foto atau ringkasan sebelumnya dengan foto terbaru.',
].join('\n');

function clean(value) {
  return String(value).replace(/[\u0000-\u001f]/g, ' ').slice(0, 120);
}

function shown(key, value) {
  if (typeof value === 'number') return number.format(value);
  if (key.endsWith('_date') && /^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(Date.parse(value))) return date.format(Date.parse(value));
  return clean(value);
}

function valueText(key, field) {
  const value = field.normalized_value ?? field.raw_value;
  if (value == null) return 'belum terbaca';
  return shown(key, value) + (field.unit === 'kg' && (typeof value === 'number' || !/\bkg\s*$/i.test(value)) ? ' kg' : '');
}

function line(key, field) {
  if (!labels[key] || !field || ['NOT_PRESENT', 'NOT_YET_FILLED'].includes(field.status)) return null;
  const needsCheck = ['AMBIGUOUS', 'ILLEGIBLE'].includes(field.status);
  return `• ${labels[key]} — ${valueText(key, field)}${needsCheck ? ' (perlu dicek)' : ''}`;
}

export function summary(revision, page = 1) {
  if (!terminal.has(revision.processing_status)) return 'Foto sudah masuk dan sedang diproses. Saya akan kirim ringkasannya di chat ini.';
  if (revision.issues?.some(({ code }) => code === 'DOCUMENT_REFERENCE_REQUIRED')) {
    return 'Apakah ini lanjutan nota produksi? Balas foto atau ringkasan nota sebelumnya dengan foto terbaru. Jika ini nota baru, kirim foto terpisah dengan caption BARU.';
  }
  const followUp = revision.follow_up?.comment ? `Catatan admin — ${clean(revision.follow_up.comment)}` : null;
  const retake = revision.photo_retake_allowed
    ? 'Jika ingin mengganti foto, balas pesan ini dengan foto baru dan caption FOTO ULANG.' : null;
  if (!revision.extraction) {
    const serviceFailed = revision.processing_status === 'FAILED_FINAL';
    return [followUp, serviceFailed
      ? 'Foto asli sudah tersimpan. Pembacaan otomatis sedang bermasalah dan foto masuk antrean pemeriksaan manual admin.'
      : 'Foto sudah tersimpan. Kolom nota belum bisa saya baca dengan yakin. Admin bisa memeriksa foto asli.',
    serviceFailed ? 'Untuk membaca ulang foto yang sama, balas ringkasan otomatis dengan COBA LAGI.' :
      'Jika memotret ulang, usahakan kertas rata, semua judul kolom terlihat, dan pencahayaan merata.', retake].filter(Boolean).join('\n');
  }
  const note = revision.extraction;
  const production = note.document_type === 'PRODUCTION_NOTE';
  const sections = [`*Draf Nota ${production ? 'Produksi' : 'Kedatangan Truk'}* · revisi ${revision.version ?? 1}`];
  const header = Object.entries(note.header ?? {}).flatMap(([key, value]) => line(key, value) ?? []);
  const batches = (note.cane_blocks ?? []).flatMap((block, i) => (block.batches ?? []).map((batch, j) => ({ block, batch, i, j })));
  const pageSize = 6;
  const pages = Math.max(1, Math.ceil(batches.length / pageSize));
  if (!Number.isInteger(page) || page < 1 || page > pages) return `Pilih halaman 1–${pages} dengan STATUS <nomor halaman>.`;
  if (page === 1) sections.push(...header);
  if (production) {
    sections.push(`${note.cane_blocks?.length ?? 0} blok tebu · ${batches.length} baris masak · halaman ${page}/${pages}`);
    let lastBlock = -1;
    for (const { block, batch, i, j } of batches.slice((page - 1) * pageSize, page * pageSize)) {
      if (i !== lastBlock) {
        lastBlock = i;
        const label = block.cane_label?.normalized_value;
        sections.push(`Blok ${i + 1}${label ? ` — ${clean(label)}` : ''}`);
      }
      const values = { pan_number: batch.pan_number, brix: batch.brix, ...batch.cooking, ...batch.output };
      const parts = Object.entries(values).flatMap(([key, field]) => line(key, field)?.slice(2) ?? []);
      sections.push(`• Baris ${j + 1}${parts.length ? `: ${parts.join(' · ')}` : ' — perlu dicek'}`);
    }
    if (page < pages) sections.push(`Ketik STATUS ${page + 1} untuk halaman berikutnya.`);
  }
  const question = revision.pending_question;
  if (followUp && page === 1) sections.push(followUp);
  if (question && page === 1) {
    const key = question.field_path?.split('.').at(-1);
    sections.push(`*Perlu dicek — ${labels[key] ?? 'kolom nota'}*`);
    if (question.candidates?.length) sections.push(`Kemungkinan bacaan — ${question.candidates.map(value => shown(key ?? '', value)).join(' / ')}`);
    sections.push('Balas ringkasan otomatis dengan JAWAB diikuti nilainya. Contoh JAWAB 1250.');
  }
  if (revision.operator_status === 'PENDING' && page === pages) {
    sections.push('Jika data sudah sesuai, balas ringkasan otomatis ini dengan KONFIRMASI.');
  } else if (revision.operator_status === 'CONFIRMED') {
    sections.push('Sudah dikonfirmasi dan masuk antrean admin.');
  } else if (revision.operator_status !== 'PENDING') {
    sections.push('Draf memerlukan pemeriksaan sebelum konfirmasi.');
  }
  if (retake && page === 1) sections.push(retake);
  return sections.join('\n');
}
