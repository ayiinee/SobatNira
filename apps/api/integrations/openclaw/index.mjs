import { open, realpath } from 'node:fs/promises';
import { isAbsolute, relative } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const uuid = '[a-f0-9-]{36}';
const command = new RegExp(`^(STATUS|KONFIRMASI|KOREKSI)\\s+(${uuid})\\s+(${uuid})(?:\\s+(.+))?$`, 'i');
const maxBytes = 10 * 1024 * 1024;
const terminal = new Set(['EXTRACTED', 'NEEDS_CLARIFICATION', 'MANUAL_REVIEW_REQUIRED', 'FAILED_FINAL']);

function asPhone(input) {
  const value = typeof input === 'string' ? input.replace(/@s\.whatsapp\.net$/, '') : '';
  const match = /^\+?([1-9][0-9]{7,14})$/.exec(value);
  return match ? `+${match[1]}` : null;
}

async function attachment(root, path) {
  const actual = await realpath(path);
  const within = relative(await realpath(root), actual);
  if (!within || within.startsWith('..') || isAbsolute(within)) throw new Error('MEDIA_PATH_OUTSIDE_STAGING');
  const file = await open(actual, 'r');
  try {
    const info = await file.stat();
    if (!info.isFile() || info.size === 0 || info.size > maxBytes) throw new Error('MEDIA_SIZE');
    const target = Buffer.alloc(info.size + 1);
    const { bytesRead } = await file.read(target, 0, target.length, 0);
    if (bytesRead !== info.size) throw new Error('MEDIA_CHANGED');
    return target.subarray(0, bytesRead);
  } finally {
    await file.close();
  }
}

function draftLines(value, path = '') {
  if (!value || typeof value !== 'object') return [];
  if ('normalized_value' in value && 'raw_value' in value) {
    const text = String(value.normalized_value ?? value.raw_value ?? '—').replace(/[\r\n\u0000-\u001f]/g, ' ').slice(0, 120);
    return [`${path}: ${text}${value.unit ? ` ${value.unit}` : ''} [${value.status}]`];
  }
  return Object.entries(value).flatMap(([key, child]) => draftLines(child, path ? `${path}.${key}` : key));
}

function summary(revision, document, id, page = 1) {
  if (!terminal.has(revision.processing_status)) return 'Foto masih dalam antrean pemrosesan.';
  if (revision.issues?.some((issue) => issue.code === 'DOCUMENT_REFERENCE_REQUIRED')) {
    return ['Pilih dokumen sebelumnya dengan mengirim ulang satu foto berjudul REVISI <ID dokumen>, atau kirim dengan caption BARU untuk nota baru.',
      ...(revision.candidate_documents ?? []).map((candidate) => `REVISI ${candidate}`)].join('\n');
  }
  if (!revision.extraction) return 'Draf belum dapat dibaca. Periksa foto, lalu kirim ulang dengan gambar yang jelas.';
  id = revision.id ?? id;
  const lines = draftLines(revision.extraction);
  const pageSize = 20;
  const pages = Math.max(1, Math.ceil(lines.length / pageSize));
  if (!Number.isInteger(page) || page < 1 || page > pages) return `Pilih halaman antara 1 dan ${pages}.`;
  const sections = [`Draf ${revision.extraction.document_type} · revisi ${revision.version} · halaman ${page}/${pages}`,
    ...lines.slice((page - 1) * pageSize, page * pageSize)];
  if (revision.follow_up?.comment) sections.push(`Alasan pengembalian: ${revision.follow_up.comment}`);
  if (page < pages) sections.push(`STATUS ${document} ${id} ${page + 1}`);
  if (revision.operator_status === 'PENDING' && page === pages) {
    sections.push(`KONFIRMASI ${document} ${id}`, `KOREKSI ${document} ${id} <field_path>=<nilai JSON>`);
  } else if (revision.operator_status === 'CONFIRMED') sections.push('Draf telah dikonfirmasi dan masuk antrean admin.');
  else if (revision.operator_status !== 'PENDING') sections.push('Draf memerlukan tinjauan sebelum konfirmasi.');
  return sections.join('\n');
}

export function createBridge({ apiUrl, token, mediaDir, request = fetch }) {
  const call = async (endpoint, options = {}, messageId) => {
    const headers = { ...options.headers, 'X-Internal-Service-Token': token };
    if (messageId) headers['Idempotency-Key'] = `baileys:${messageId}`;
    const result = await request(new URL(`/internal/v1/whatsapp/${endpoint}`, apiUrl), {
      ...options, headers, signal: AbortSignal.timeout(14_000), redirect: 'error',
    });
    if (!result.ok) {
      const reason = (await result.json().catch(() => null))?.message;
      const response = result.status === 403 ? 'Nomor operator belum aktif.' :
        result.status === 429 ? 'Terlalu banyak kiriman. Tunggu sebentar dan coba lagi.' :
        reason === 'DOCUMENT_REFERENCE_REQUIRED' || reason === 'DOCUMENT_REFERENCE_CONFLICT' ? 'Rujuk ID nota produksi atau gunakan caption BARU.' :
        result.status === 409 ? 'Pilihan atau revisi berubah. Periksa ID dan ambil draf aktif.' :
        result.status < 500 ? 'Metadata, foto, atau perintah tidak dapat diterima. Periksa kembali.' : 'SobatNira sementara tidak tersedia. Coba lagi.';
      throw new BridgeError(response);
    }
    return result.json();
  };

  const status = (phone, document, revision) => call(`documents/${document}/revisions/${revision}`, { headers: { 'X-Operator-Phone': phone } });

  async function handle(event, context) {
    const phone = asPhone(event.metadata?.senderE164) ?? asPhone(event.senderId) ?? asPhone(context.senderId);
    const messageId = event.messageId ?? context.messageId;
    const chatId = event.conversationId ?? context.conversationId;
    const timestamp = typeof event.timestamp === 'number' ? new Date(event.timestamp < 1e12 ? event.timestamp * 1_000 : event.timestamp) : null;
    if (!phone || !messageId || typeof chatId !== 'string' || !timestamp || !Number.isFinite(timestamp.valueOf())) {
      return { text: 'Identitas atau metadata pengirim WhatsApp belum tersedia.' };
    }
    const content = (event.body ?? event.content ?? '').trim();
    const metadata = { provider: 'BAILEYS', provider_message_id: messageId, chat_id: chatId,
      sender_phone_e164: phone, provider_timestamp: timestamp.toISOString(),
      quoted_message_id: event.replyToId ?? context.replyToId ?? null, caption: content || null };
    if (event.mediaStagingPending) return { text: 'Foto belum dapat diunduh. Coba kirim ulang.' };

    try {
      if (event.media?.length) {
        const [media] = event.media;
        if (event.media.length !== 1 || !media.path || !['image/jpeg', 'image/png'].includes(media.contentType)) {
          return { text: 'Kirim tepat satu foto JPEG atau PNG.' };
        }
        let bytes;
        try { bytes = await attachment(mediaDir, media.path); }
        catch { return { text: 'Foto tidak dapat dibuka. Kirim ulang satu foto yang valid.' }; }
        const form = new FormData();
        form.set('event', JSON.stringify({ ...metadata, message_type: 'IMAGE', media_mime_type: media.contentType }));
        form.set('media', new Blob([bytes], { type: media.contentType }), 'nota');
        const accepted = await call('inbound', { method: 'POST', body: form }, messageId);
        return { text: `Foto diterima. Cek dengan STATUS ${accepted.document_id} ${accepted.revision_id}`,
          pending: accepted.duplicate ? null : { phone, document: accepted.document_id, revision: accepted.revision_id } };
      }
      const parsed = command.exec(content);
      if (!parsed) return { text: 'Kirim satu foto nota atau gunakan perintah STATUS, KOREKSI, atau KONFIRMASI dari ringkasan draf.' };
      const [, verb, document, revision, tail] = parsed;
      if (verb.toUpperCase() === 'STATUS') return { text: summary(await status(phone, document, revision), document, revision, Number(tail ?? 1)) };
      const action = { action: 'CONFIRM', document_id: document.toLowerCase(), revision_id: revision.toLowerCase() };
      if (verb.toUpperCase() === 'KOREKSI') {
        const correction = /^([a-z0-9_.]+)=(.+)$/i.exec(tail ?? '');
        if (!correction) return { text: 'Gunakan KOREKSI <dokumen> <revisi> <field_path>=<nilai JSON>.' };
        try { Object.assign(action, { action: 'CORRECT', field_path: correction[1], value: JSON.parse(correction[2]) }); }
        catch { return { text: 'Gunakan angka JSON atau apit nilai teks dengan tanda kutip.' }; }
      }
      const result = await call('text-events', { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ event: { ...metadata, message_type: 'TEXT' }, action }) }, messageId);
      return { text: action.action === 'CONFIRM' ? 'Draf dikonfirmasi dan masuk antrean admin.' :
        summary(await status(phone, document, result.revision_id), document, result.revision_id) };
    } catch (error) {
      return { text: error instanceof BridgeError ? error.message : 'SobatNira sementara tidak tersedia. Coba lagi.' };
    }
  }
  return { handle, status };
}

class BridgeError extends Error {}

export default {
  id: 'sobatnira-intake',
  name: 'SobatNira Intake',
  register(api) {
    const { accountId, mediaDir } = api.pluginConfig ?? {};
    const apiUrl = process.env.SOBATNIRA_API_URL;
    const token = process.env.WHATSAPP_ADAPTER_INTERNAL_TOKEN;
    if (!apiUrl || !token || !accountId || !mediaDir) throw new Error('SobatNira bridge configuration is incomplete');
    const bridge = createBridge({ apiUrl, token, mediaDir });
    const system = api.runtime.system;
    const waiting = new Map();
    api.on('inbound_claim', async (event, context) => {
      if (event.channel !== 'whatsapp' || (event.accountId ?? context.accountId ?? 'default') !== accountId) return;
      if (event.isGroup) return { handled: true, reply: { text: 'Kirim nota melalui chat langsung.' } };
      const result = await bridge.handle(event, context);
      const sessionKey = context.sessionKey;
      const agentId = context.agentId ?? /^agent:([^:]+):/.exec(sessionKey ?? '')?.[1];
      if (result.pending && agentId && sessionKey && waiting.size < 16 && !waiting.has(result.pending.revision) &&
          system?.captureSessionGeneration && system?.postSessionNotice) {
        const { phone, document, revision } = result.pending;
        const task = (async () => {
          const generation = await system.captureSessionGeneration({ agentId, sessionKey });
          if (!generation) return;
          for (let attempt = 0; attempt < 45; attempt++) {
            await delay(4_000, undefined, { ref: false });
            const current = await bridge.status(phone, document, revision).catch(() => null);
            if (!current || !terminal.has(current.processing_status)) continue;
            await system.postSessionNotice({ generation, idempotencyKey: `sobatnira:${revision}`,
              notice: { type: 'document-draft', text: summary(current, document, revision) }, deliver: {} });
            return;
          }
        })().catch(() => api.logger.warn('SobatNira draft notice unavailable')).finally(() => waiting.delete(revision));
        waiting.set(revision, task);
      }
      return { handled: true, reply: { text: result.text } };
    });
  },
};
