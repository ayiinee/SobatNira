import { createIntentAgent } from './operator-agent.mjs';

const reportIntents = ['SUMMARY', 'GRADES', 'METRICS', 'UNKNOWN'];
const ownerTool = { type: 'function', function: {
  name: 'select_owner_view',
  description: 'Select a read-only production view using the supplied vocabulary.',
  strict: true,
  parameters: { type: 'object', properties: { intent: { type: 'string', enum: reportIntents } },
    required: ['intent'], additionalProperties: false },
} };
const vocabulary = new Set('jumlah total ringkasan produksi gula petakan distribusi kelompok grade rendemen biaya operasional margin nilai metrik'.split(' '));
export const createOwnerSelector = config => createIntentAgent(config, reportIntents, ownerTool,
  'Select a read-only production view. GRADES shows grade distribution. METRICS shows lot yield, value, costs, and margin. SUMMARY shows factory official totals. Use UNKNOWN if uncertain. Return no facts or values.');

const explanationIntents = ['CAKUPAN', 'SUMBER', 'RINGKAS'];
const explanationTool = { type: 'function', function: {
  name: 'select_owner_explanation',
  description: 'Select an explanation focus for an authorized result using categorical metadata.',
  strict: true,
  parameters: { type: 'object', properties: { intent: { type: 'string', enum: explanationIntents } },
    required: ['intent'], additionalProperties: false },
} };
export const createOwnerNarrator = config => createIntentAgent(config, explanationIntents, explanationTool,
  'Select CAKUPAN to explain missing or partial data, SUMBER for source context, or RINGKAS. Return only an enum. Never infer facts.');

const day = 86_400_000;
const jakarta = 7 * 3_600_000;
const dateId = value => new Date(value + jakarta).toISOString().slice(0, 10);
function interval(value, now) {
  const shifted = new Date(now + jakarta);
  const midnight = Date.UTC(shifted.getUTCFullYear(), shifted.getUTCMonth(), shifted.getUTCDate()) - jakarta;
  let from, before;
  if (/\bkemarin\b/.test(value)) { from = midnight - day; before = midnight; }
  else if (/\bhari ini\b/.test(value)) { from = midnight; before = midnight + day; }
  else if (/\bminggu (?:ini|lalu)\b/.test(value)) {
    const current = midnight - (shifted.getUTCDay() + 6) % 7 * day;
    from = value.includes('minggu lalu') ? current - 7 * day : current;
    before = from + 7 * day;
  } else if (/\bbulan (?:ini|lalu)\b/.test(value)) {
    const index = shifted.getUTCMonth() - Number(value.includes('bulan lalu'));
    from = Date.UTC(shifted.getUTCFullYear(), index, 1) - jakarta;
    before = Date.UTC(shifted.getUTCFullYear(), index + 1, 1) - jakarta;
  } else {
    const exact = /^\d{4}-\d{2}-\d{2}$/.exec(value);
    if (!exact) return undefined;
    from = Date.parse(`${value}T00:00:00+07:00`);
    if (!Number.isFinite(from) || dateId(from) !== value) return undefined;
    before = from + day;
  }
  return { from: new Date(from).toISOString(), before: new Date(before).toISOString() };
}

const help = 'Contoh: ASISTEN produksi kemarin, ASISTEN distribusi grade minggu ini, ASISTEN bandingkan bulan ini dan bulan lalu, ASISTEN telusuri batch <ID>, atau ASISTEN buat laporan minggu ini.';
const operations = { SUMMARY: 'get_production_summary', GRADES: 'get_grade_distribution', METRICS: 'get_production_metrics' };
const missing = {
  incomplete_consumed_nira: 'Peringkat belum tersedia karena debit nira tidak cocok dengan volume batch sah.',
  official_rework_link: 'Relasi masak ulang resmi belum tersedia.',
  consumed_nira: 'Debit nira belum tercatat.', approved_intake: 'Penerimaan sah belum tersedia.',
  approved_milling: 'Penggilingan sah belum tersedia.', earlier_revisions: 'Sebagian riwayat tersedia pada halaman berikutnya.',
  additional_contribution_rows: 'Masih ada baris kontribusi di halaman berikutnya.',
};
const show = value => value ?? 'Belum tersedia';
function totals(row) {
  return [`Kloter: ${show(row.lotCount)} · batch: ${show(row.batchCount)}`,
    `Tebu diterima: ${show(row.caneNetKg)} kg · gula final: ${show(row.finalSugarKg)} kg`,
    `Nilai produksi: Rp${show(row.productionValueRupiah)} · biaya: Rp${show(row.totalCostRupiah)}`,
    `Margin produksi: Rp${show(row.productionMarginRupiah)} (sementara jika kloter masih terbuka)`];
}

function explain({ operation, result, data_status, missing_relations, sources, correlation_id }, focus) {
  if (data_status === 'no_data') return `Belum ada data pada lingkup ini.\nReferensi permintaan: ${correlation_id}`;
  const lines = [];
  if (result.from) lines.push(`Periode ${dateId(Date.parse(result.from))} sampai sebelum ${dateId(Date.parse(result.before))} WIB`);
  if (result.totals) lines.push(...totals(result.totals));
  if (result.grades && !result.batchId) lines.push(...result.grades.slice(0, 10).map(g => `Grade ${g.code}: ${g.weightKg} kg · Rp${g.exactValueRupiah}`));
  if (result.contributions?.status === 'complete') {
    const { leaders, leadingCount, unit } = result.contributions;
    lines.push(leadingCount > 1 ? `Ada ${leadingCount} kloter asal dengan kontribusi nira terbesar yang sama.` : 'Kontribusi nira terbesar');
    for (const row of leaders) lines.push(`Kloter ${row.lotCode} (${row.originLotId}): ${row.quantityMl} ${unit}`);
    if (leadingCount > leaders.length) lines.push('Daftar kloter dengan nilai sama dipersingkat.');
    lines.push('Periode mengikuti tanggal penerimaan kloter batch. Asal mengikuti ledger debit nira.');
  }
  if (result.contributions?.status === 'no_data') lines.push('Belum ada debit nira untuk peringkat periode ini.');
  if (result.first) {
    for (const item of [result.first, result.second]) {
      lines.push(`Periode ${dateId(Date.parse(item.from))} sampai sebelum ${dateId(Date.parse(item.before))} WIB`, ...totals(item.totals));
    }
  }
  if (result.lotMetrics) lines.push(...result.lotMetrics.slice(0, 5).map(r => `Kloter ${r.lotId}: rendemen ${r.rendemenPercent}%`));
  if (operation === 'get_lot_traceability') {
    lines.push(`Kloter ${result.code ?? result.id}`);
    for (const [label, record] of [['Penerimaan', result.intake], ['Penggilingan', result.milling]]) {
      if (record) lines.push(`${label}: ${record.document.documentId} · revisi ${show(record.document.revisionId)}`);
    }
  }
  if (result.batchId) lines.push(`Batch ${result.code} · kloter ${result.lotId} · wajan ${result.wokNumber}`);
  if (result.revisions) lines.push(...result.revisions.slice(0, 5).map(r =>
    `Revisi ${r.version} · ${r.revision_id} · ${r.review_status ?? r.processing_status}`));
  if (result.items) lines.push(...result.items.slice(0, 5).map(r => `${r.originLotId} → ${r.batchId}: ${r.quantityMl} mL`));
  if (result.pageConsumedQuantityMl) lines.push(`Kontribusi pada halaman ini: ${result.pageConsumedQuantityMl} mL`);
  if ((result.items?.length ?? 0) > 5 || (result.lotMetrics?.length ?? 0) > 5 || (result.revisions?.length ?? 0) > 5 ||
    (result.grades?.length ?? 0) > 10) lines.push('Cuplikan ditampilkan di chat. Lihat rincian di SobatNira.');
  for (const relation of missing_relations) if (missing[relation]) lines.push(missing[relation]);
  const reference = sources.find(s => s.snapshotId || s.id);
  if (reference) lines.push(`Sumber: ${reference.snapshotId ?? reference.id}`);
  if (focus === 'CAKUPAN') lines.push('Cakupan mengikuti sumber yang sudah tercatat dan status data di atas.');
  if (focus === 'SUMBER' && reference) lines.push('Referensi sumber dapat diperiksa di SobatNira.');
  lines.push(`Referensi permintaan: ${correlation_id}`);
  return lines.join('\n');
}

export async function ownerReply(content, execute, select, now = Date.now(), narrate) {
  const text = content.trim().toLowerCase();
  const status = /^status laporan ([a-f0-9-]{36})$/.exec(text);
  if (status) return reportStatus(await execute({ action: 'report-status', reportId: status[1] }));
  const requestedPeriod = /\b(kemarin|hari ini|minggu ini|minggu lalu|bulan ini|bulan lalu|\d{4}-\d{2}-\d{2})\b/.exec(text);
  const selectedPeriod = requestedPeriod && interval(requestedPeriod[1], now);
  if (/^buat laporan\b/.test(text)) return selectedPeriod ?
    reportStatus(await execute({ action: 'report-request', query: selectedPeriod })) : help;
  const references = [...text.matchAll(/\b(kloter|batch|dokumen) ([a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12})\b/g)];
  if (references.length > 1) return 'Sebutkan satu UUID kloter, batch, atau dokumen per pertanyaan.';
  const [reference] = references;
  const wantsRanking = /\b(terbesar|terbanyak)\b/.test(text) && /\b(kontribusi|penyumbang)\b/.test(text);
  const namedBasis = /\bnira\b/.test(text) && /\b(tanggal|waktu) penerimaan kloter batch\b/.test(text);
  let operation, args;
  if (reference) {
    const [, kind, id] = reference;
    if (kind === 'kloter') {
      operation = /kontribusi|asal nira/.test(text) ? 'get_lot_contribution_summary' : 'get_lot_traceability';
      args = { lotId: id };
    } else if (kind === 'batch') {
      operation = /kontribusi|asal nira/.test(text) ? 'get_material_contributions' : 'get_batch_traceability';
      args = { batchId: id };
    } else { operation = 'get_document_lineage'; args = { documentId: id }; }
  } else if (/\bbandingkan\b/.test(text)) {
    const terms = text.replace(/[.!?]+$/, '').replace(/^.*?\bbandingkan\s+/, '').split(/\s+(?:dan|dengan)\s+/);
    const [first, second] = terms.map(term => interval(term, now));
    if (terms.length !== 2 || !first || !second) return help;
    operation = 'compare_production_periods';
    args = { first, second };
  } else if (wantsRanking || (/\b(total|ringkasan|jumlah)\b/.test(text) && /\bgrade\b/.test(text))) {
    if (!selectedPeriod) return help;
    operation = 'get_production_insight';
    args = { ...selectedPeriod, ...(wantsRanking && namedBasis ? { contributionBasis: 'consumed_nira_by_lot_received_at' } : {}) };
  } else {
    args = selectedPeriod;
    if (!args || /\b(telusuri|asal|kontribusi)\b/.test(text)) return help;
    let intent = /\bgrade\b/.test(text) ? 'GRADES' :
      /\b(rendemen|nilai|biaya|margin|metrik)\b/.test(text) ? 'METRICS' :
      /\b(produksi|gula)\b/.test(text) ? 'SUMMARY' : 'UNKNOWN';
    if (intent === 'UNKNOWN' && select) {
      const words = (text.match(/[a-z]+/g) ?? []).filter(word => vocabulary.has(word));
      if (words.length) {
        await execute({ action: 'check' });
        const picked = await select([...new Set(words)].join(' '));
        if (picked && Object.hasOwn(operations, picked)) intent = picked;
      }
    }
    operation = operations[intent];
    if (!operation) return help;
  }
  const answer = await execute({ action: 'query', query: { operation, arguments: args } });
  const focus = narrate && /\bjelaskan\b/.test(text)
    ? await narrate(answer.data_status === 'partial' ? 'PARTIAL' : answer.data_status === 'no_data' ? 'NO_DATA' : 'COMPLETE')
    : undefined;
  const message = explain(answer, focus);
  if (operation === 'get_production_insight' && wantsRanking && !namedBasis) {
    return `${message}\nUntuk peringkat, apakah yang dimaksud kontribusi nira berdasarkan tanggal penerimaan kloter batch? Sebutkan basis itu dan periodenya.`;
  }
  return message;
}

function reportStatus(job) {
  if (job.status === 'READY') return `Laporan ${job.id} siap dalam PDF dan XLSX. Unduh dengan sesi owner di SobatNira.`;
  if (job.status === 'FAILED') return `Ekspor laporan ${job.id} gagal. Ajukan permintaan baru untuk mencoba lagi.`;
  return `Laporan sedang diproses. Ketik ASISTEN status laporan ${job.id} untuk mengecek hasilnya.`;
}
