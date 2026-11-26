import pino from 'pino';
import { maskObject } from './mask';

/** pino logger that masks phones, licence numbers and message text in every logged object. */
export function createLogger(level: string, pretty = false) {
  return pino({
    level,
    redact: { paths: ['req.headers.authorization', 'password', 'refreshToken', 'accessToken'], censor: '[redacted]' },
    formatters: { log: (obj) => maskObject(obj) as Record<string, unknown> },
    ...(pretty ? { transport: { target: 'pino-pretty', options: { singleLine: true } } } : {}),
  });
}
export type Logger = ReturnType<typeof createLogger>;
