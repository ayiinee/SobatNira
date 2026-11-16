import { open, realpath } from 'node:fs/promises';
import { isAbsolute, relative } from 'node:path';
import { createOperatorAgent } from './operator-agent.mjs';

const uuid = '[a-f0-9-]{36}';
const command = new RegExp(`^(STATUS|KONFIRMASI|KOREKSI|JAWAB)\\s+(${uuid})\\s+(${uuid})(?:\\s+(.+))?$`, 'i');
const answer = new RegExp(`^(${uuid})\\s+(.+)$`, 'i');
const maxBytes = 10 * 1024 * 1024;
const terminal = new Set(['EXTRACTED', 'NEEDS_CLARIFICATION', 'MANUAL_REVIEW_REQUIRED', 'FAILED_FINAL']);
const operatorHelp = 'Kirim satu foto nota atau gunakan perintah STATUS, KOREKSI, atau KONFIRMASI dari ringkasan draf.';

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
  id = revision.id ?? id;
  const retake = `Kirim satu foto dengan caption FOTO ULANG ${document} ${id}.`;
  if (!revision.extraction) return [revision.follow_up?.comment ? `Alasan pengembalian: ${revision.follow_up.comment}` :
    'Draf belum dapat dibaca. Pastikan semua kolom terlihat dan foto cukup terang.',
    ...(revision.photo_retake_allowed ? [retake] : [])].join('\n');
  const lines = draftLines(revision.extraction);
  const pageSize = 20;
  const pages = Math.max(1, Math.ceil(lines.length / pageSize));
  if (!Number.isInteger(page) || page < 1 || page > pages) return `Pilih halaman antara 1 dan ${pages}.`;
  const sections = [`Draf ${revision.extraction.document_type} · revisi ${revision.version} · halaman ${page}/${pages}`,
    `STATUS ${document} ${id}`, ...lines.slice((page - 1) * pageSize, page * pageSize)];
  if (revision.follow_up?.comment) sections.push(`Alasan pengembalian: ${revision.follow_up.comment}`);
  const question = revision.pending_question;
  if (question && page === 1) {
    sections.push(`Periksa nilai ${question.field_path}${question.unit ? ` (${question.unit})` : ''}.`);
    if (question.candidates.length) sections.push(`Kandidat pembacaan: ${question.candidates.map((value) => JSON.stringify(value)).join(' / ')}`);
    sections.push(`JAWAB ${document} ${id} ${question.id} <nilai JSON>`);
  }
  if (revision.photo_retake_allowed && page === 1) sections.push(retake);
  if (page < pages) sections.push(`STATUS ${document} ${id} ${page + 1}`);
  if (revision.operator_status === 'PENDING' && page === pages) {
    sections.push(`KONFIRMASI ${document} ${id}`, `KOREKSI ${document} ${id} <field_path>=<nilai JSON>`);
  } else if (revision.operator_status === 'CONFIRMED') sections.push('Draf telah dikonfirmasi dan masuk antrean admin.');
  else if (revision.operator_status !== 'PENDING') sections.push('Draf memerlukan tinjauan sebelum konfirmasi.');
  return sections.join('\n');
}

export function createBridge({ apiUrl, token, mediaDir, request = fetch, classifyIntent }) {
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
      throw new BridgeError(response, result.status);
    }
    return result.json();
  };

  const status = (phone, document, revision) => call(`documents/${document}/revisions/${revision}`, { headers: { 'X-Operator-Phone': phone } });

  async function help(phone, chat, quote, content) {
    if (!quote || !classifyIntent) return operatorHelp;
    const target = await call('quoted-context', { headers: { 'X-Operator-Phone': phone, 'X-Chat-Id': chat, 'X-Quoted-Message-Id': quote } })
      .catch(() => null);
    if (!target) return operatorHelp;
    const { document_id: document, revision_id: id } = target;
    const revision = await status(phone, document, id);
    if (!terminal.has(revision.processing_status)) return summary(revision, document, id);
    const intent = await classifyIntent(content);
    const commandTarget = `${document} ${revision.id ?? id}`;
    switch (intent) {
      case 'SHOW_DRAFT':
        return summary(revision, document, id);
      case 'EXPLAIN_ISSUE': {
        if (revision.pending_question) return summary(revision, document, id);
        const lines = draftLines(revision.extraction).filter((line) => /\[(ILLEGIBLE|AMBIGUOUS)\]$/.test(line));
        if (lines.length) return [`Bidang yang perlu diperiksa:`, ...lines.slice(0, 3), `Lihat draf lengkap dengan STATUS ${commandTarget}`].join('\n');
        return summary(revision, document, id);
      }
      case 'GUIDE_CORRECTION':
        if (revision.operator_status === 'PENDING') return `Periksa draf dengan STATUS ${commandTarget}, lalu gunakan KOREKSI ${commandTarget} <field_path>=<nilai JSON>.`;
        return summary(revision, document, id);
      case 'GUIDE_CONFIRMATION':
        if (revision.operator_status === 'PENDING') return `Periksa semua halaman dengan STATUS ${commandTarget}. Perintah konfirmasi tersedia pada halaman terakhir.`;
        return summary(revision, document, id);
      case 'RETAKE_PHOTO':
        return revision.photo_retake_allowed ? `Potret semua kolom dengan cahaya merata. Kirim dengan caption FOTO ULANG ${commandTarget}.` :
          'Foto ulang tidak tersedia untuk revisi ini. Periksa status draf.';
      default:
        return operatorHelp;
    }
  }

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
        return { text: `Foto diterima. Cek dengan STATUS ${accepted.document_id} ${accepted.revision_id}` };
      }
      const parsed = command.exec(content);
      if (!parsed) return { text: await help(phone, chatId, metadata.quoted_message_id, content) };
      const [, verb, document, revision, tail] = parsed;
      if (verb.toUpperCase() === 'STATUS') return { text: summary(await status(phone, document, revision), document, revision, Number(tail ?? 1)) };
      const action = { action: 'CONFIRM', document_id: document.toLowerCase(), revision_id: revision.toLowerCase() };
      if (verb.toUpperCase() === 'KOREKSI') {
        const correction = /^([a-z0-9_.]+)=(.+)$/i.exec(tail ?? '');
        if (!correction) return { text: 'Gunakan KOREKSI <dokumen> <revisi> <field_path>=<nilai JSON>.' };
        try { Object.assign(action, { action: 'CORRECT', field_path: correction[1], value: JSON.parse(correction[2]) }); }
        catch { return { text: 'Gunakan angka JSON atau apit nilai teks dengan tanda kutip.' }; }
      }
      if (verb.toUpperCase() === 'JAWAB') {
        const reply = answer.exec(tail ?? '');
        if (!reply) return { text: 'Gunakan JAWAB <dokumen> <revisi> <pertanyaan> <nilai JSON> dari ringkasan draf.' };
        try { Object.assign(action, { action: 'ANSWER', question_id: reply[1].toLowerCase(), value: JSON.parse(reply[2]) }); }
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
  async function deliverNotice(send) {
    const { notice } = await call('notices/claim', { method: 'POST' });
    if (!notice) return false;
    let outcome = 'RETRY';
    let receipt;
    try {
      const revision = await status(notice.phone_e164, notice.document_id, notice.revision_id);
      if (revision.id !== notice.revision_id || (notice.kind === 'OCR_RESULT' && revision.operator_status === 'CONFIRMED')) {
        outcome = 'CANCELLED';
      } else {
        const text = summary(revision, notice.document_id, notice.revision_id);
        receipt = await send({ to: notice.phone_e164, text, replyToId: notice.reply_to_id });
        outcome = 'SENT';
      }
    } catch (error) {
      if (error instanceof BridgeError && error.status === 404) outcome = 'CANCELLED';
    }
    await call(`notices/${notice.id}/result`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ claim_token: notice.claim_token, outcome, provider_message_id: receipt }) });
    return true;
  }
  return { handle, status, deliverNotice };
}

class BridgeError extends Error {
  constructor(message, status) { super(message); this.status = status; }
}

export default {
  id: 'sobatnira-intake',
  name: 'SobatNira Intake',
  register(api) {
    const { accountId, mediaDir } = api.pluginConfig ?? {};
    const apiUrl = process.env.SOBATNIRA_API_URL;
    const token = process.env.WHATSAPP_ADAPTER_INTERNAL_TOKEN;
    const mode = process.env.SOBATNIRA_MODE;
    if (mode !== 'local' && mode !== 'connected') throw new Error('OpenClaw: SOBATNIRA_MODE wajib');
    const connected = mode === 'connected';
    const target = URL.canParse(apiUrl ?? '') ? new URL(apiUrl) : null;
    if (!target || !['https:', 'http:'].includes(target.protocol) || target.username || target.password ||
        !token || token.length < 32 || !accountId || !mediaDir || !isAbsolute(mediaDir) ||
        (connected && process.env.SOBATNIRA_WHATSAPP_ACCOUNT_ID !== accountId)) {
      throw new Error('OpenClaw: periksa SOBATNIRA_API_URL, WHATSAPP_ADAPTER_INTERNAL_TOKEN, SOBATNIRA_WHATSAPP_ACCOUNT_ID dan konfigurasi accountId/mediaDir');
    }
    let classifyIntent;
    try {
      classifyIntent = createOperatorAgent({ key: process.env.OPENROUTER_API_KEY, model: process.env.OPENROUTER_AGENT_MODEL,
        fallbackModel: process.env.OPENROUTER_AGENT_FALLBACK_MODEL, providers: process.env.OPENROUTER_ALLOWED_PROVIDERS });
    } catch {
      if (connected) throw new Error('OpenRouter: periksa OPENROUTER_AGENT_MODEL, OPENROUTER_AGENT_FALLBACK_MODEL, OPENROUTER_ALLOWED_PROVIDERS');
      api.logger.warn('Konfigurasi OpenRouter tidak lengkap. Panduan operator memakai template.');
    }
    if (connected && !classifyIntent) throw new Error('OpenRouter: OPENROUTER_API_KEY wajib');
    if (!api.runtime.channel?.outbound?.loadAdapter || !api.registerService) {
      throw new Error('OpenClaw: SDK outbound dan registerService wajib');
    }
    const bridge = createBridge({ apiUrl, token, mediaDir, classifyIntent });
    let timer;
    let inFlight;
    const send = async ({ to, text, replyToId }) => {
      const whatsapp = await api.runtime.channel.outbound.loadAdapter('whatsapp');
      if (!whatsapp?.sendText) throw new Error('WhatsApp outbound adapter unavailable');
      const result = await whatsapp.sendText({
        cfg: api.config, accountId, to, text, replyToId, signal: AbortSignal.timeout(12_000),
      });
      if (typeof result?.messageId !== 'string' || !result.messageId) throw new Error('WhatsApp provider receipt unavailable');
      return result.messageId;
    };
    api.registerService({ id: 'sobatnira-notices', start() {
      timer = setInterval(() => {
        if (!inFlight) inFlight = bridge.deliverNotice(send).catch(() => api.logger.warn('SobatNira notice queue unavailable'))
          .finally(() => { inFlight = undefined; });
      }, 2_000);
      timer.unref();
    }, async stop() { clearInterval(timer); await inFlight; } });
    api.on('reply_dispatch', async (event, context) => {
      const inbound = event.ctx;
      if ((event.originatingChannel ?? inbound.Provider) !== 'whatsapp' ||
          (event.originatingAccountId ?? inbound.AccountId) !== accountId) return;
      const direct = (event.originatingChatType ?? inbound.ChatType) === 'direct';
      let queuedFinal = false;
      if (direct && event.sendPolicy === 'allow') {
        const phone = asPhone(inbound.SenderE164) ?? asPhone(inbound.SenderId);
        const result = await bridge.handle({
          senderId: phone,
          conversationId: phone,
          messageId: inbound.MessageSid ?? inbound.ProviderMessageId,
          timestamp: inbound.ProviderMessageTimestamp ?? inbound.Timestamp,
          body: inbound.BodyForCommands ?? inbound.RawBody ?? '',
          replyToId: inbound.ReplyToId,
          media: inbound.media,
          mediaStagingPending: inbound.mediaStagingPending,
        }, {});
        queuedFinal = !event.suppressUserDelivery && context.dispatcher.sendFinalReply({ text: result.text });
      }
      context.recordProcessed('completed', { reason: 'sobatnira_intake' });
      return { handled: true, queuedFinal, counts: context.dispatcher.getQueuedCounts() };
    }, { eligibleDispatchKinds: ['agent'], timeoutMs: 35_000 });
  },
};
