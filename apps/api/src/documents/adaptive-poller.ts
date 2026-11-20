type Schedule = (work: () => Promise<void>, milliseconds: number) => () => void;
const scheduleTimer: Schedule = (work, milliseconds) => {
  const timer = setTimeout(() => { void work(); }, milliseconds);
  timer.unref();
  return () => clearTimeout(timer);
};

export function documentPollSettings(env: NodeJS.ProcessEnv = process.env) {
  const integer = (name: string, fallback: number) => {
    const raw = env[name] ?? String(fallback), value = Number(raw);
    if (!/^\d+$/.test(raw) || !Number.isSafeInteger(value) || value < 50 || value > 30000) throw new Error(`Konfigurasi tidak valid: ${name}`);
    return value;
  };
  const minMs = integer('DOCUMENT_POLL_MIN_MS', 500);
  const maxMs = integer('DOCUMENT_POLL_MAX_MS', 500);
  if (maxMs < minMs) throw new Error('DOCUMENT_POLL_MAX_MS harus >= DOCUMENT_POLL_MIN_MS');
  return { minMs, maxMs };
}

// Serial work, bounded idle/error backoff, and shutdown that waits for in-flight work.
export class AdaptivePoller {
  private cancel?: () => void;
  private running?: Promise<void>;
  private stopped = false;
  private started = false;
  private delayMs: number;
  private polls = 0;
  private empty = 0;
  private errors = 0;
  constructor(private readonly work: () => Promise<boolean>, private readonly settings: { minMs: number; maxMs: number },
    private readonly onError: () => void, private readonly schedule: Schedule = scheduleTimer) {
    this.delayMs = settings.minMs;
  }
  statistics() { return { polls: this.polls, empty: this.empty, errors: this.errors, idleDelayMs: this.delayMs }; }
  start() { if (!this.started) { this.started = true; this.arm(this.delayMs); } }
  private arm(delay: number) { if (!this.stopped) this.cancel = this.schedule(() => this.tick(), delay); }
  private async tick() {
    if (this.stopped) return;
    this.running = (async () => {
      this.polls++;
      let found = false;
      try { found = await this.work(); if (!found) this.empty++; }
      catch { this.errors++; this.onError(); }
      this.delayMs = found ? this.settings.minMs : Math.min(this.settings.maxMs, this.delayMs * 2);
      // Yield the event loop when draining backlog; never run another claim concurrently.
      this.arm(found ? 0 : this.delayMs);
    })();
    await this.running;
  }
  async stop() { this.stopped = true; this.cancel?.(); await this.running; }
}
