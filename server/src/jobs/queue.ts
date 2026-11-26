// Background jobs (spec §9.6). QUEUE_MODE=inline runs them in this process; bullmq uses Redis and `npm run worker`.
// Same jobId = same job: a second enqueue while one is waiting or running is ignored.
import { Queue, Worker, type Job } from 'bullmq';
import { Redis } from 'ioredis';
import type { Logger } from '../lib/logger';

export type JobName = 'transcribe' | 'structure' | 'notify';

export interface JobHandlers {
  run: (name: JobName, data: unknown) => Promise<void>;
  /** Called once after the last attempt fails. */
  failed: (name: JobName, data: unknown, err: Error) => Promise<void>;
}

export interface JobQueue {
  enqueue<T>(name: JobName, data: T, opts?: { jobId?: string }): Promise<void>;
  /** Resolves when nothing is queued or running (inline driver; used by tests). */
  idle(): Promise<void>;
  close(): Promise<void>;
}

/** Wait before attempt n+1: 1 s, 4 s, 16 s, ... (`unitMs` shrinks it in tests). */
export const backoffMs = (attempt: number, unitMs = 1000) => unitMs * 4 ** (attempt - 1);

export function inlineQueue(handlers: JobHandlers, opts: { maxAttempts: number; log: Logger; unitMs?: number }): JobQueue {
  const active = new Set<string>();
  const running = new Set<Promise<void>>();
  const timers = new Set<NodeJS.Timeout>();
  let closed = false;

  const attempt = (name: JobName, data: unknown, key: string, n: number): Promise<void> => {
    const p = (async () => {
      try {
        await handlers.run(name, data);
        active.delete(key);
      } catch (e) {
        const err = e as Error;
        if (n < opts.maxAttempts && !closed) {
          opts.log.warn({ job: name, attempt: n, err: err.message }, 'job failed, retrying');
          const t = setTimeout(() => { timers.delete(t); void attempt(name, data, key, n + 1); }, backoffMs(n, opts.unitMs));
          timers.add(t);
          return;
        }
        active.delete(key);
        opts.log.error({ job: name, attempts: n, err: err.message }, 'job failed for good');
        await handlers.failed(name, data, err).catch((f) => opts.log.error({ err: (f as Error).message }, 'job failure handler failed'));
      }
    })();
    running.add(p);
    void p.finally(() => running.delete(p));
    return p;
  };

  return {
    async enqueue(name, data, o) {
      const key = o?.jobId ?? `${name}:${Math.random()}`;
      if (closed || active.has(key)) return;
      active.add(key);
      setImmediate(() => void attempt(name, data, key, 1));
    },
    async idle() {
      while (active.size || running.size) await new Promise((r) => setTimeout(r, 10));
    },
    async close() {
      closed = true;
      timers.forEach(clearTimeout);
      await Promise.allSettled([...running]);
    },
  };
}

const QUEUE = 'taskplus';

/** Producer side of BullMQ: the API only adds jobs. */
export function bullmqQueue(redisUrl: string, maxAttempts: number): JobQueue {
  const connection = new Redis(redisUrl, { maxRetriesPerRequest: null });
  const queue = new Queue(QUEUE, { connection });
  return {
    async enqueue(name, data, o) {
      await queue.add(name, data, {
        jobId: o?.jobId?.replace(/:/g, '-'), // BullMQ ids may not contain ':'
        attempts: maxAttempts,
        backoff: { type: 'custom' },
        removeOnComplete: 1000,
        removeOnFail: false, // failed jobs stay as the dead-letter list
      });
    },
    async idle() {
      const pending = async () => Object.values(await queue.getJobCounts('waiting', 'active', 'delayed', 'prioritized')).reduce((a, b) => a + b, 0);
      while (await pending()) await new Promise((r) => setTimeout(r, 50));
    },
    async close() { await queue.close(); connection.disconnect(); },
  };
}

/** Consumer side: `npm run worker` (or tests) run this. */
export function bullmqWorker(redisUrl: string, handlers: JobHandlers, opts: { log: Logger; unitMs?: number; concurrency?: number }) {
  const connection = new Redis(redisUrl, { maxRetriesPerRequest: null });
  const worker = new Worker(QUEUE, async (job: Job) => handlers.run(job.name as JobName, job.data), {
    connection,
    concurrency: opts.concurrency ?? 5,
    settings: { backoffStrategy: (attemptsMade: number) => backoffMs(attemptsMade, opts.unitMs) },
  });
  worker.on('failed', (job, err) => {
    if (!job) return;
    if (job.attemptsMade >= (job.opts.attempts ?? 1)) void handlers.failed(job.name as JobName, job.data, err);
    else opts.log.warn({ job: job.name, attempt: job.attemptsMade, err: err.message }, 'job failed, retrying');
  });
  return { close: async () => { await worker.close(); connection.disconnect(); } };
}
