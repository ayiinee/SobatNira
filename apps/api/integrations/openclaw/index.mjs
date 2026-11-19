import { open, realpath } from 'node:fs/promises';
import { isAbsolute, relative } from 'node:path';
import { createOperatorAgent } from './operator-agent.mjs';
import { answerExample, operatorHelp, operatorInstructions, reference, summary, terminal } from './operator-copy.mjs';

const uuid = '[a-f0-9-]{36}';
const command = new RegExp(`^(STATUS|KONFIRMASI|KOREKSI|JAWAB)\\s+(${uuid})\\s+(${uuid})(?:\\s+(.+))?$`, 'i');
const answer = new RegExp(`^(${uuid})\\s+(.+)$`, 'i');
const maxBytes = 10 * 1024 * 1024;
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

export function createBridge({ apiUrl, token, mediaDir, request = fetch, classifyIntent, observe = () => {} }) {
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
        reason === 'DOCUMENT_REFERENCE_REQUIRED' || reason === 'DOCUMENT_REFERENCE_CONFLICT' ? 'Untuk lanjutan, balas ringkasan nota sebelumnya dengan foto. Untuk nota baru, kirim terpisah dengan caption BARU.' :
        reason === 'OCR_RETRY_UNAVAILABLE' ? 'Foto ini sudah diproses atau belum bisa dicoba ulang. Ketik STATUS untuk melihat hasil terbaru.' :
        reason === 'OPERATOR_CLARIFICATION_REQUIRED' ? 'Masih ada data yang perlu diperiksa. Balas ringkasan nota dengan STATUS untuk melihat pertanyaan yang aktif.' :
        reason === 'OPERATOR_DOCUMENT_BLOCKED' ? 'Draf perlu diperiksa sebelum dikonfirmasi. Balas ringkasan nota dengan STATUS untuk melihat langkah berikutnya.' :
        reason === 'OPERATOR_ANSWER_INVALID' || reason === 'Field atau nilai koreksi tidak valid' ?
          'Nilainya belum sesuai. Balas ringkasan nota dengan STATUS untuk melihat contoh jawaban.' :
        result.status === 409 ? 'Pilihan atau revisi berubah. Ketik STATUS atau balas ringkasan terbaru.' :
        result.status < 500 ? 'Metadata, foto, atau perintah tidak dapat diterima. Periksa kembali.' : 'SobatNira sementara tidak tersedia. Coba lagi.';
      throw new BridgeError(response, result.status);
    }
    return result.json();
  };

  const status = (phone, document, revision) => call(`documents/${document}/revisions/${revision}`, { headers: { 'X-Operator-Phone': phone } });
  const contextFor = (phone, chat, quote, action = false) => call(
    quote ? `quoted-context${action ? '?action=true' : ''}` : 'latest-context',
    { headers: { 'X-Operator-Phone': phone, 'X-Chat-Id': chat, ...(quote ? { 'X-Quoted-Message-Id': quote } : {}) } },
  ).catch((error) => {
    if (error instanceof BridgeError && error.status === 404) return null;
    throw error;
  });

  async function showStatus(phone, chat, document, revisionId, page) {
    const revision = await status(phone, document, revisionId);
    let retryQueued = false;
    if (revision.notice_retry_available && !['PENDING_VALIDATION','VALIDATED'].includes(revision.workflow_status)) {
      const result = await call(`documents/${document}/revisions/${revision.id}/retry-notice`, {
        method: 'POST', headers: { 'X-Operator-Phone': phone, 'X-Chat-Id': chat, 'Content-Type': 'application/json' },
        body: JSON.stringify({ question_id: revision.pending_question?.id }),
      }).catch(() => null);
      retryQueued = result?.queued === true;
    }
    return summary(revision, page, { fromStatus: true, retryQueued });
  }

  async function help(phone, chat, quote, content) {
    if (!quote || !classifyIntent) return operatorHelp;
    const target = await contextFor(phone, chat, quote);
    if (!target) return operatorHelp;
    const { document_id: document, revision_id: id } = target;
    const revision = await status(phone, document, id);
    if (!terminal.has(revision.processing_status)) return summary(revision);
    const intent = await classifyIntent(content);
    switch (intent) {
      case 'SHOW_DRAFT':
      case 'EXPLAIN_ISSUE':
        return summary(revision, 1, { fromStatus: true });
      case 'GUIDE_CORRECTION':
        return revision.pending_question ? summary(revision, 1, { fromStatus: true }) :
          'Jika ada data yang perlu dikoreksi, beri tahu admin sebelum validasi. Ketik STATUS untuk memeriksa draf.';
      case 'GUIDE_CONFIRMATION':
        if (revision.can_confirm) return 'Ketik STATUS untuk memeriksa draf. Jika datanya sesuai, balas ringkasan otomatis dengan KONFIRMASI.';
        return summary(revision, 1, { fromStatus: true });
      case 'RETAKE_PHOTO':
        return revision.photo_retake_allowed ? 'Balas ringkasan otomatis dengan satu foto baru dan caption FOTO ULANG.' :
          'Foto ulang tidak tersedia untuk revisi ini. Periksa status draf.';
      default:
        return operatorHelp;
    }
  }

  async function handle(event, context) {
    const started = performance.now();
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
        if (/^FOTO ULANG$/i.test(content)) {
          const quote = metadata.quoted_message_id;
          const target = quote && await contextFor(phone, chatId, quote, true);
          if (!target) return { text: 'Balas ringkasan otomatis nota yang ingin difoto ulang dengan foto baru dan caption FOTO ULANG.' };
          metadata.caption = `FOTO ULANG ${target.document_id} ${target.revision_id}`;
        }
        const form = new FormData();
        form.set('event', JSON.stringify({ ...metadata, message_type: 'IMAGE', media_mime_type: media.contentType }));
        form.set('media', new Blob([bytes], { type: media.contentType }), 'nota');
        const accepted = await call('inbound', { method: 'POST', body: form }, messageId);
        const acceptedAt = performance.now();
        observe({ event: 'whatsapp_photo_accepted', revisionId: accepted.revision_id,
          duplicate: accepted.duplicate, elapsedMs: Math.round(acceptedAt - started) });
        const label = reference(accepted.document_id);
        return { text: accepted.duplicate
          ? `Foto ini sudah tercatat ${label}. Balas foto yang Anda kirim dengan *STATUS* untuk melihat nota ini.`
          : `Foto diterima. Sedang membaca nota… ${label}\nSaya akan kirim hasilnya di chat ini. Ketik *STATUS* untuk cek progres.`,
        photoReceipt: { revisionId: accepted.revision_id, duplicate: accepted.duplicate,
          adapterStarted: started, eventTimestamp: timestamp.valueOf(), acceptedAt,
          commitConfirmedAtMs: accepted.commit_confirmed_at_ms } };
      }
      const quote = metadata.quoted_message_id;
      const shortStatus = /^STATUS(?:\s+(\d+))?$/i.exec(content);
      if (shortStatus) {
        const target = await contextFor(phone, chatId, quote);
        if (!target) return { text: quote ? 'Ringkasan ini sudah berubah atau tidak ditemukan. Ketik STATUS sebagai pesan baru.' :
          'Belum ada nota di chat ini. Kirim satu foto untuk mulai.' };
        return { text: await showStatus(phone, chatId, target.document_id, target.revision_id, Number(shortStatus[1] ?? 1)) };
      }
      if (/^(BANTUAN|HELP|MENU)$/i.test(content)) return { text: operatorInstructions };
      if (/^(OK[EY]?|SIAP|TERIMA KASIH|MAKASIH)[.!]*$/i.test(content)) {
        return { text: 'Siap. Ketik STATUS kapan saja untuk melihat nota terakhir.' };
      }
      let parsed = command.exec(content);
      const shortAction = !parsed && /^(KONFIRMASI|JAWAB|COBA LAGI)(?:\s+(.+))?$/i.exec(content);
      if (shortAction) {
        const [, verb, value] = shortAction;
        const target = quote && await contextFor(phone, chatId, quote, true);
        if (!target) return { text: 'Balas ringkasan otomatis yang terbaru agar perintah diterapkan pada nota yang tepat.' };
        let tail;
        if (verb.toUpperCase() === 'JAWAB') {
          const active = await status(phone, target.document_id, target.revision_id);
          if (!value || !active.pending_question || active.id !== target.revision_id) {
            return { text: 'Periksa pertanyaan pada ringkasan terbaru. Balas dengan JAWAB diikuti nilainya.' };
          }
          if (target.question_id !== active.pending_question.id) {
            return { text: 'Pesan ini tidak memuat pertanyaan yang aktif. Balas pesan ini dengan STATUS untuk meminta ringkasan terbaru.' };
          }
          const path = active.pending_question.field_path;
          const input = value.trim();
          const numeric = /(?:^|\.)(?:net_weight_kg|isi_kg|hasil_kg|brix)$/.test(path);
          if (numeric && (!/^\d+(?:,\d+|\.\d{1,2})?$/.test(input) ||
              /^\d{1,3}(?:\.\d{3})+(?:,\d+)?$/.test(input))) {
            return { text: `Tulis angka tanpa pemisah ribuan. Contoh JAWAB ${answerExample(path)}. Untuk desimal, gunakan koma.` };
          }
          const normalized = numeric ? Number(input.replace(',', '.')) : input;
          if (numeric && (!Number.isFinite(normalized) || (path === 'header.net_weight_kg' && normalized <= 0))) {
            return { text: `Periksa kembali nilainya pada nota. Contoh JAWAB ${answerExample(path)}.` };
          }
          tail = `${active.pending_question.id} ${JSON.stringify(normalized)}`;
        } else if (value) return { text: `Balas ringkasan hanya dengan ${verb.toUpperCase()}.` };
        parsed = [null, verb, target.document_id, target.revision_id, tail];
      }
      if (!parsed) return { text: await help(phone, chatId, quote, content) };
      const [, verb, document, revision, tail] = parsed;
      if (verb.toUpperCase() === 'STATUS') return { text: await showStatus(phone, chatId, document, revision, Number(tail ?? 1)) };
      const action = { action: verb.toUpperCase() === 'COBA LAGI' ? 'RETRY_OCR' : 'CONFIRM',
        document_id: document.toLowerCase(), revision_id: revision.toLowerCase() };
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
      if (action.action === 'RETRY_OCR') return { text: 'Foto asli masuk antrean pembacaan ulang. Saya akan mengirim ringkasannya di sini.' };
      return { text: action.action === 'CONFIRM' ? 'Draf dikonfirmasi dan masuk antrean admin.' :
        shortAction ? 'Jawaban tersimpan. Saya akan mengirim ringkasan terbaru.' :
          summary(await status(phone, document, result.revision_id), 1, { fromStatus: true }) };
    } catch (error) {
      if (event.media?.length && (!(error instanceof BridgeError) || error.status >= 500)) {
        return { text: 'Saya belum bisa memastikan foto masuk. Balas foto itu dengan STATUS untuk memeriksa kiriman.' };
      }
      return { text: error instanceof BridgeError ? error.message : 'SobatNira sementara tidak tersedia. Coba lagi.' };
    }
  }
  async function deliverNotice(send) {
    const { notice } = await call('notices/claim', { method: 'POST' });
    if (!notice) return false;
    const started = performance.now();
    let outcome = 'RETRY';
    let receipt;
    let createdAt;
    let photoRecordedAt;
    let questionId;
    try {
      const revision = await status(notice.phone_e164, notice.document_id, notice.revision_id);
      createdAt = Date.parse(revision.created_at);
      photoRecordedAt = Date.parse(revision.photo_recorded_at);
      if (revision.id !== notice.revision_id || ['PENDING_VALIDATION','VALIDATED'].includes(revision.workflow_status) ||
          (notice.kind === 'OCR_RESULT' && (revision.operator_status === 'CONFIRMED' ||
            revision.workflow_status === 'RETURNED_FOR_CORRECTION'))) {
        outcome = 'CANCELLED';
      } else {
        const text = summary(revision);
        receipt = await send({ to: notice.phone_e164, text, replyToId: notice.reply_to_id });
        questionId = revision.pending_question?.id;
        outcome = 'SENT';
      }
    } catch (error) {
      if (error instanceof BridgeError && error.status === 404) outcome = 'CANCELLED';
    }
    await call(`notices/${notice.id}/result`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ claim_token: notice.claim_token, outcome, provider_message_id: receipt, question_id: questionId }) });
    observe({ event: 'whatsapp_notice_delivery', revisionId: notice.revision_id,
      kind: notice.kind, outcome, elapsedMs: Math.round(performance.now() - started),
      ...(outcome === 'SENT' && Number.isFinite(createdAt) ? { revisionToProviderAckMs: Math.max(0, Date.now() - createdAt) } : {}),
      ...(outcome === 'SENT' && Number.isFinite(photoRecordedAt)
        ? { photoRecordedToProviderAckMs: Math.max(0, Date.now() - photoRecordedAt) } : {}) });
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
    const localHttp = target?.protocol === 'http:' && ['127.0.0.1', 'localhost', '[::1]'].includes(target.hostname);
    if (!target || (target.protocol !== 'https:' && !localHttp) || target.username || target.password ||
        target.search || target.hash || target.pathname !== '/' ||
        !token || token.length < 32 || !accountId || !mediaDir || !isAbsolute(mediaDir) ||
        (connected && process.env.SOBATNIRA_WHATSAPP_ACCOUNT_ID !== accountId)) {
      throw new Error('OpenClaw: periksa SOBATNIRA_API_URL, WHATSAPP_ADAPTER_INTERNAL_TOKEN, SOBATNIRA_WHATSAPP_ACCOUNT_ID dan konfigurasi accountId/mediaDir');
    }
    let classifyIntent;
    const disableReasoning = process.env.OPENROUTER_AGENT_DISABLE_REASONING;
    try {
      if (disableReasoning && !['true', 'false'].includes(disableReasoning)) throw new Error('Invalid reasoning configuration');
      classifyIntent = createOperatorAgent({ key: process.env.OPENROUTER_API_KEY, model: process.env.OPENROUTER_AGENT_MODEL,
        fallbackModel: process.env.OPENROUTER_AGENT_FALLBACK_MODEL, providers: process.env.OPENROUTER_ALLOWED_PROVIDERS,
        disableReasoning: disableReasoning === 'true' });
    } catch {
      if (connected) throw new Error('OpenRouter: periksa OPENROUTER_AGENT_MODEL, OPENROUTER_AGENT_FALLBACK_MODEL, OPENROUTER_ALLOWED_PROVIDERS, OPENROUTER_AGENT_DISABLE_REASONING');
      api.logger.warn('Konfigurasi OpenRouter tidak lengkap. Panduan operator memakai template.');
    }
    if (connected && !classifyIntent) throw new Error('OpenRouter: OPENROUTER_API_KEY wajib');
    if (!api.runtime.channel?.outbound?.loadAdapter || !api.registerService) {
      throw new Error('OpenClaw: SDK outbound dan registerService wajib');
    }
    const observe = (event) => api.logger.info?.(JSON.stringify(event));
    const bridge = createBridge({ apiUrl, token, mediaDir, classifyIntent, observe });
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
        if (result.photoReceipt) {
          const { revisionId, duplicate, adapterStarted, eventTimestamp, acceptedAt, commitConfirmedAtMs } = result.photoReceipt;
          const dispatchedAt = Date.now();
          observe({ event: 'whatsapp_photo_reply_dispatch', revisionId, duplicate, queued: Boolean(queuedFinal),
            adapterToDispatchMs: Math.round(performance.now() - adapterStarted),
            messageToDispatchMs: Math.max(0, dispatchedAt - eventTimestamp),
            ...(queuedFinal ? { apiResponseToDispatchMs: Math.round(performance.now() - acceptedAt) } : {}),
            ...(queuedFinal && !duplicate && Number.isFinite(commitConfirmedAtMs) && dispatchedAt >= commitConfirmedAtMs
              ? { commitToDispatchMs: dispatchedAt - commitConfirmedAtMs } : {}) });
        }
      }
      context.recordProcessed('completed', { reason: 'sobatnira_intake' });
      return { handled: true, queuedFinal, counts: context.dispatcher.getQueuedCounts() };
    }, { eligibleDispatchKinds: ['agent', 'acp'], timeoutMs: 35_000 });
    api.on('before_agent_run', (event, context) => {
      if ((event.channelId ?? context.channel) === 'whatsapp' && (event.accountId ?? context.accountId) === accountId) {
        return { outcome: 'block', reason: 'sobatnira_uses_document_workflow', message: operatorHelp };
      }
    });
    api.on('reply_payload_sending', (event, context) => {
      if ((event.channel ?? context.channelId) === 'whatsapp' && context.accountId === accountId &&
          /couldn.t sign in to the AI service/i.test(event.payload.text ?? '')) {
        return { payload: { ...event.payload, text: operatorHelp } };
      }
    });
  },
};
