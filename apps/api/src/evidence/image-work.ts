import { ServiceUnavailableException } from '@nestjs/common';

export class ImageWorkLimiter {
  private active = 0;
  private readonly waiting: (() => void)[] = [];
  constructor(private readonly concurrency = 1, private readonly queueLimit = 4) {}
  statistics() { return { active: this.active, waiting: this.waiting.length }; }
  async run<T>(work: () => Promise<T>): Promise<T> {
    if (this.active >= this.concurrency) {
      if (this.waiting.length >= this.queueLimit) throw new ServiceUnavailableException('Pemrosesan foto sibuk; coba lagi.');
      await new Promise<void>(resolve => this.waiting.push(resolve));
    } else this.active++;
    try { return await work(); }
    finally { const next = this.waiting.shift(); if (next) next(); else this.active--; }
  }
}

// Shared by uploads and variant reads. Acquire before reading storage, not after.
export const imageWork = new ImageWorkLimiter();
