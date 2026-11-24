import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { IncomingMessage, ServerResponse } from 'node:http';
import { performance } from 'node:perf_hooks';
import { DurationHistogram } from './durations';

type Request = IncomingMessage & { route?: { path?: string } };
type RouteStats = { duration: DurationHistogram; responses: number; errors: number; aborted: number; knownBodyBytes: number; unknownBodyResponses: number };

@Injectable()
export class HttpMeasurements implements OnModuleDestroy {
  private readonly routes = new Map<string, RouteStats>();
  private readonly logger = new Logger(HttpMeasurements.name);
  private readonly sampler: NodeJS.Timeout;
  constructor() {
    this.sampler = setInterval(() => this.logger.debug({ event: 'http_metrics', routes: this.snapshot() }), 30000);
    this.sampler.unref();
  }
  middleware(request: Request, response: ServerResponse, next: () => void) {
    const start = performance.now(); let recorded = false;
    const finish = (aborted: boolean) => {
      if (recorded) return; recorded = true;
      const method = ['GET', 'POST', 'PATCH', 'PUT', 'DELETE', 'HEAD', 'OPTIONS'].includes(request.method ?? '') ? request.method : 'OTHER';
      // Express route patterns contain placeholders. Never label by raw URL/query.
      const label = `${method} ${request.route?.path ?? '<unmatched>'}`;
      const key = this.routes.has(label) || this.routes.size < 255 ? label : '<other-routes>';
      let stats = this.routes.get(key);
      if (!stats) { stats = { duration: new DurationHistogram(), responses: 0, errors: 0, aborted: 0, knownBodyBytes: 0, unknownBodyResponses: 0 }; this.routes.set(key, stats); }
      stats.duration.observe(performance.now() - start); stats.responses++;
      if (aborted) stats.aborted++; else if (response.statusCode >= 400) stats.errors++;
      const header = response.getHeader('content-length');
      const size = request.method === 'HEAD' || [204, 304].includes(response.statusCode) ? 0 :
        typeof header === 'number' ? header : typeof header === 'string' && /^\d+$/.test(header) ? Number(header) : NaN;
      if (!aborted && Number.isSafeInteger(size) && size >= 0) stats.knownBodyBytes += size;
      else stats.unknownBodyResponses++;
    };
    response.once('finish', () => finish(false)); response.once('close', () => finish(true));
    next();
  }
  snapshot() { return [...this.routes].map(([route, { duration, ...stats }]) => ({ route, ...stats, durationMs: duration.snapshot() })); }
  onModuleDestroy() { clearInterval(this.sampler); }
}
