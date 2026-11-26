// Prometheus counters (spec §12), served at /metrics.
import { Counter, Gauge, Histogram, Registry, collectDefaultMetrics } from 'prom-client';

export function createMetrics() {
  const registry = new Registry();
  collectDefaultMetrics({ register: registry });
  return {
    registry,
    aiJobs: new Counter({ name: 'ai_jobs_total', help: 'AI structuring results', labelNames: ['status', 'provider'] as const, registers: [registry] }),
    aiLatency: new Histogram({ name: 'ai_latency_ms', help: 'LLM call time in ms', labelNames: ['provider', 'ok'] as const,
      buckets: [250, 500, 1000, 2000, 4000, 8000, 12000, 20000], registers: [registry] }),
    queueDepth: new Gauge({ name: 'queue_depth', help: 'Jobs waiting or running', registers: [registry] }),
  };
}
export type Metrics = ReturnType<typeof createMetrics>;
