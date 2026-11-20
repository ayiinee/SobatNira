const BOUNDS = [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 30000, 60000, 300000, Infinity];

// Fixed memory, approximate percentile upper bounds, no request/query samples.
export class DurationHistogram {
  private readonly buckets = BOUNDS.map(() => 0);
  private count = 0;
  private totalMs = 0;
  private maxMs = 0;
  observe(milliseconds: number) {
    if (!Number.isFinite(milliseconds) || milliseconds < 0) return;
    this.count++; this.totalMs += milliseconds; this.maxMs = Math.max(this.maxMs, milliseconds);
    this.buckets[BOUNDS.findIndex(bound => milliseconds <= bound)]++;
  }
  private percentile(fraction: number) {
    if (!this.count) return null;
    const rank = Math.ceil(this.count * fraction); let cumulative = 0;
    for (let n = 0; n < BOUNDS.length; n++) {
      cumulative += this.buckets[n];
      if (cumulative >= rank) return Number.isFinite(BOUNDS[n]) ? BOUNDS[n] : null;
    }
    return null;
  }
  snapshot() {
    return { count: this.count, totalMs: this.totalMs, maxMs: this.maxMs,
      p50UpperBoundMs: this.percentile(0.5), p95UpperBoundMs: this.percentile(0.95), p99UpperBoundMs: this.percentile(0.99),
      buckets: BOUNDS.map((bound, n) => ({ upperMs: Number.isFinite(bound) ? bound : null, count: this.buckets[n] })) };
  }
}
