import { describe, expect, it } from 'vitest';
import { loadEnv, requireKey } from '../src/config/env';
import { parseDatabaseUrl } from '../src/db/client';
import { maskDigits, maskId, maskObject } from '../src/lib/mask';
import { normalisePhone } from '../src/modules/auth/routes';

const base = { DATABASE_URL: 'mssql://u:p@localhost:1433/taskplus', JWT_SECRET: 'x'.repeat(32) };

describe('settings', () => {
  it('fills defaults and reads switches', () => {
    const e = loadEnv({ ...base, QUEUE_MODE: 'bullmq' });
    expect(e.QUEUE_MODE).toBe('bullmq');
    expect(e.REALTIME_MODE).toBe('memory');
    expect(e.SLA_HOURS_HIGH).toBe(4);
  });
  it('lists every problem in one message', () => {
    expect(() => loadEnv({ JWT_SECRET: 'short' })).toThrow(/DATABASE_URL[\s\S]*JWT_SECRET/);
  });
  it('refuses DEV_FIXED_OTP in production', () => {
    expect(() => loadEnv({ ...base, NODE_ENV: 'production', DEV_FIXED_OTP: '123456' })).toThrow(/DEV_FIXED_OTP: must not be set/);
  });
  it('asks for a provider key only when it is used', () => {
    expect(() => requireKey(loadEnv(base), 'GEMINI_API_KEY')).toThrow(/GEMINI_API_KEY is not set/);
  });
  it('reads the database URL', () => {
    expect(parseDatabaseUrl('mssql://sa:p%40ss@db:1433/tp?trustServerCertificate=true'))
      .toMatchObject({ server: 'db', port: 1433, database: 'tp', userName: 'sa', password: 'p@ss', encrypt: true, trustServerCertificate: true });
  });
});

describe('masking', () => {
  it('keeps only the last digits of phones and the ends of licence numbers', () => {
    expect(maskDigits('+91 98765 43210')).toBe('**********10');
    expect(maskId('LIC-ABC-12345')).toBe('LI***45');
  });
  it('masks nested fields and never logs message text', () => {
    const out = maskObject({ task: { customer_phone: '9876543210', license_no: 'ABCD1234', bodyText: 'secret words' }, code: 'ALREADY_ACCEPTED' });
    expect(out).toEqual({ task: { customer_phone: '********10', license_no: 'AB***34', bodyText: '[12 chars]' }, code: 'ALREADY_ACCEPTED' });
  });
});

describe('phone numbers', () => {
  it('drops +91 and a leading 0', () => {
    expect(normalisePhone('+91 98000 00001')).toBe('9800000001');
    expect(normalisePhone('09800000001')).toBe('9800000001');
    expect(normalisePhone('98000-00001')).toBe('9800000001');
  });
});
