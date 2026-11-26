// Kysely on SQL Server through tedious, from DATABASE_URL.
import { Kysely, MssqlDialect } from 'kysely';
import * as tarn from 'tarn';
import * as tedious from 'tedious';
import type { Database } from './schema';

/** mssql://user:pass@host:1433/db?encrypt=true&trustServerCertificate=true -> tedious settings */
export function parseDatabaseUrl(url: string) {
  const u = new URL(url);
  if (u.protocol !== 'mssql:') throw new Error('DATABASE_URL must start with mssql://');
  const flag = (k: string, d: boolean) => (u.searchParams.has(k) ? u.searchParams.get(k) === 'true' : d);
  return {
    server: u.hostname,
    port: Number(u.port || 1433),
    database: decodeURIComponent(u.pathname.slice(1)),
    userName: decodeURIComponent(u.username),
    password: decodeURIComponent(u.password),
    encrypt: flag('encrypt', true),
    trustServerCertificate: flag('trustServerCertificate', false),
  };
}

export function createDb(url: string) {
  const c = parseDatabaseUrl(url);
  return new Kysely<Database>({
    dialect: new MssqlDialect({
      tarn: { ...tarn, options: { min: 0, max: 10 } },
      tedious: {
        ...tedious,
        connectionFactory: () => new tedious.Connection({
          server: c.server,
          authentication: { type: 'default', options: { userName: c.userName, password: c.password } },
          options: { port: c.port, database: c.database, encrypt: c.encrypt, trustServerCertificate: c.trustServerCertificate, useUTC: true },
        }),
      },
    }),
  });
}
export type Db = ReturnType<typeof createDb>;
