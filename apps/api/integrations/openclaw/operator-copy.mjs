const labels = {
  arrival_date: 'Tanggal datang', supplier_name: 'Pemasok', vehicle_number: 'Nomor kendaraan',
  brix: 'Brix', net_weight_kg: 'Berat bersih', cane_type: 'Jenis tebu',
  receiving_operator: 'Operator pada nota', production_date: 'Tanggal produksi',
  shift: 'Sif', chef: 'Petugas masak', cane_label: 'Label tebu', pan_number: 'Wajan',
  isi_kg: 'Isi', gamping: 'Gamping', jam_turun: 'Jam turun', grade: 'Grade', hasil_kg: 'Berat hasil',
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
  return String(value).replace(/[\u0000-\u001f*_`~]/g, ' ').slice(0, 120);
}

function shown(key, value) {
  if (typeof value === 'number') return number.format(value);
  if (key.endsWith('_date') && /^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(Date.parse(value))) return date.format(Date.parse(value));
  return clean(value);
}

function valueText(key, field) {
  if (field.status === 'NOT_YET_FILLED') return 'Belum dicatat';
  if (['AMBIGUOUS','ILLEGIBLE'].includes(field.status)) return 'perlu dicek';
  const value = field.normalized_value;
  if (value == null) return 'belum terbaca';
  return shown(key, value) + (field.unit === 'kg' && (typeof value === 'number' || !/\bkg\s*$/i.test(value)) ? ' kg' : '');
}

function line(key, field) {
  if (!labels[key] || !field || ['NOT_PRESENT','BLANK'].includes(field.status)) return null;
  return `• ${labels[key]} — ${valueText(key, field)}`;
}

export function reference(id) {
  return typeof id === 'string' ? `#${id.slice(0, 8).toUpperCase()}` : '';
}

function fieldContext(note, path) {
  const parts = path.split('.');
  if (parts[0] !== 'cane_blocks') return '';
  const block = note.cane_blocks?.[Number(parts[1])];
  const row = block?.batches?.[Number(parts[3])];
  const label = block?.cane_label;
  const pan = row?.pan_number;
  return [
    label?.status === 'READ' && label.normalized_value ? `Blok ${clean(label.normalized_value)}` : `Blok ${Number(parts[1]) + 1}`,
    row && (pan?.status === 'READ' && pan.normalized_value != null ? `Wajan ${clean(pan.normalized_value)}` : `Baris ${Number(parts[3]) + 1}`),
  ].filter(Boolean).join(' · ') + ' · ';
}

export function answerExample(path) {
  const key = path.split('.').at(-1);
  if (key?.endsWith('_date')) return '2026-11-16';
  if (key === 'jam_turun') return '09:15';
  if (key === 'supplier_name') return 'Nama Pemasok';
  if (key === 'cane_type') return 'BL';
  if (key === 'cane_label') return 'Label pada nota';
  if (key === 'vehicle_number') return 'Nomor kendaraan';
  if (key === 'grade') return 'A';
  if (key === 'pan_number') return '2';
  if (key === 'net_weight_kg') return '1250';
  if (['isi_kg','hasil_kg','gamping','brix'].includes(key)) return '25';
  return 'nilai pada nota';
}

export function summary(revision, page = 1, { fromStatus = false, retryQueued = false } = {}) {
  if (!terminal.has(revision.processing_status)) {
    return revision.processing_status === 'QUEUED'
      ? 'Foto tersimpan dan menunggu giliran baca. Saya akan kirim ringkasannya di chat ini. Ketik *STATUS* untuk cek progres.'
      : 'Foto sedang dibaca. Saya akan kirim ringkasannya di chat ini. Ketik *STATUS* untuk cek progres.';
  }
  const note = revision.extraction;
  const production = note?.document_type === 'PRODUCTION_NOTE';
  const title = note ? `Nota ${production ? 'Produksi' : 'Kedatangan Truk'}` : 'Foto nota';
  const heading = [`*${title}*`, reference(revision.document_id), `Revisi ${revision.version ?? 1}`].filter(Boolean).join(' · ');
  const target = fromStatus ? 'ringkasan otomatis nota ini' : 'pesan ini';
  if (revision.workflow_status === 'VALIDATED') return `${heading}\n*Disahkan admin.* Data sudah dibukukan.`;
  if (revision.workflow_status === 'PENDING_VALIDATION' || (!revision.workflow_status && revision.operator_status === 'CONFIRMED')) {
    return `${heading}\n*Menunggu pengesahan admin.*`;
  }
  if (revision.issues?.some(({ code }) => code === 'DOCUMENT_REFERENCE_REQUIRED')) {
    const candidates = (revision.candidate_documents ?? []).filter(id =>
      typeof id === 'string' && /^[\da-f]{8}-(?:[\da-f]{4}-){3}[\da-f]{12}$/i.test(id)).slice(0, 5);
    return ['Pilih nota tujuan sebelum foto dipakai sebagai revisi.',
      'Balas foto atau ringkasan nota tujuan dengan foto terbaru.',
      ...(candidates.length ? ['Anda juga bisa kirim ulang foto dengan caption pilihan sesuai nota tujuan:',
        ...candidates.map(id => `• ${reference(id)} — REVISI ${id}`)] : []),
      'Jika ini nota baru, kirim foto terpisah dengan caption BARU.'].join('\n');
  }
  const followUp = revision.follow_up?.comment ? `Catatan admin — ${clean(revision.follow_up.comment)}` : null;
  const returned = revision.workflow_status === 'RETURNED_FOR_CORRECTION';
  const retake = `Balas ${target} dengan foto baru dan caption *FOTO ULANG*.`;
  if (!note) {
    const serviceFailed = revision.processing_status === 'FAILED_FINAL';
    return [heading, returned ? '*Dikembalikan admin.*' : '*Perlu tinjauan manual.*', followUp,
      serviceFailed ? 'Foto asli tersimpan. Pembacaan otomatis gagal.' : 'Foto asli tersimpan. Tata letak atau bagian nota belum terbaca.',
      retryQueued ? 'Ringkasan dijadwalkan untuk dikirim ulang.' :
        serviceFailed && !returned ? `Balas ${target} dengan *COBA LAGI* untuk membaca ulang foto asli.` :
          revision.photo_retake_allowed ? `Foto ulang dengan semua judul dan tepi nota terlihat. ${retake}` :
            'Hubungi admin jika perlu memperbarui foto.'].filter(Boolean).join('\n');
  }
  const sections = [heading, returned ? '*Dikembalikan admin.*' :
    revision.can_confirm ? '*Siap dikonfirmasi.*' : '*Perlu diperiksa.*'];
  const question = revision.pending_question;
  const header = Object.entries(note.header ?? {}).flatMap(([key, value]) => line(key, value) ?? []);
  const batches = (note.cane_blocks ?? []).flatMap((block, i) => (block.batches ?? []).map((batch, j) => ({ block, batch, i, j })));
  const pageSize = 6;
  const pages = Math.max(1, Math.ceil(batches.length / pageSize));
  if (!Number.isInteger(page) || page < 1 || page > pages) return `Pilih halaman 1–${pages} dengan STATUS <nomor halaman>.`;
  if (page === 1) {
    if (question && !retryQueued) {
      const path = question.field_path;
      const key = path.split('.').at(-1);
      sections.push(`*Perlu dicek — ${fieldContext(note, path)}${labels[key] ?? 'kolom nota'}*`);
      if (question.issue_code === 'DUPLICATE_CANE_LABEL') sections.push('Label ini sama dengan blok lain. Periksa label yang tertulis pada foto.');
      if (question.issue_code === 'ILLEGIBLE_FIELD') sections.push('Bagian ini kurang jelas pada foto. Periksa nilainya di nota asli.');
      if (question.candidates?.length) sections.push(`Kemungkinan bacaan — ${question.candidates.map(value => shown(key ?? '', value)).join(' / ')}`);
      sections.push(`Balas ${target} dengan *JAWAB* diikuti nilai dari foto. Contoh JAWAB ${answerExample(path)}.`);
    }
    const changes = (revision.changed_fields ?? []).flatMap(path => {
      const key = path.split('.').at(-1);
      const field = path.split('.').reduce((value, part) => value?.[part], note);
      if (!labels[key] || !field) return [];
      return [`• ${fieldContext(note, path)}${labels[key]} — ${valueText(key, field)}`];
    });
    if (followUp) sections.push(followUp);
    if (changes.length) {
      sections.push('*Perubahan pada revisi ini*', ...changes.slice(0, 4));
      if (changes.length > 4) sections.push(`Ada ${changes.length - 4} perubahan lain pada rincian nota.`);
    }
    sections.push(...header);
  }
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
  }
  if (retryQueued) sections.push('Ringkasan dijadwalkan untuk dikirim ulang.');
  else if (page < pages) {
    sections.push(`Balas ringkasan otomatis nota ini dengan *STATUS ${page + 1}* untuk halaman berikutnya.`);
  } else if (question) {
    if (page > 1) sections.push('Balas pertanyaan pada ringkasan otomatis nota ini.');
  } else if (revision.can_confirm) {
    sections.push(`Jika data sesuai foto, balas ${page > 1 ? 'ringkasan otomatis nota ini' : target} dengan *KONFIRMASI*.`);
  } else if (revision.photo_retake_allowed) {
    if (revision.issues?.some(({ code }) => code === 'ROW_MATCH_REQUIRED')) {
      sections.push('Pastikan label tebu, nomor wajan, dan jam turun terlihat pada bagian yang berubah.');
    }
    sections.push(retake);
  } else sections.push('Hubungi admin untuk memeriksa draf ini.');
  return sections.join('\n');
}
