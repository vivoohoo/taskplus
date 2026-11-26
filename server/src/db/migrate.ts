// npm run migrate: creates the database if missing, then applies every migration not yet applied.
import { Migrator, sql, type Migration, type MigrationProvider } from 'kysely';
import { fileURLToPath } from 'node:url';
import { loadEnv } from '../config/env';
import { createDb, type Db } from './client';
import * as m0001 from './migrations/0001_init';
import * as m0002 from './migrations/0002_passwords_statuses';

/** Listed here, in order. Add each new migration file to this list. */
const MIGRATIONS: Record<string, Migration> = { '0001_init': m0001, '0002_passwords_statuses': m0002 };
const provider: MigrationProvider = { getMigrations: async () => MIGRATIONS };

export async function ensureDatabase(url: string) {
  const u = new URL(url);
  const name = decodeURIComponent(u.pathname.slice(1));
  if (!/^[A-Za-z0-9_]+$/.test(name)) throw new Error(`Database name "${name}" may only use letters, digits and _`);
  u.pathname = '/master';
  const master = createDb(u.toString());
  try { await sql.raw(`IF DB_ID('${name}') IS NULL CREATE DATABASE [${name}]`).execute(master); } finally { await master.destroy(); }
}

export async function migrateToLatest(db: Db) {
  const { error, results } = await new Migrator({ db, provider }).migrateToLatest();
  for (const r of results ?? []) if (r.status !== 'NotExecuted') console.log(`migration ${r.migrationName}: ${r.status}`);
  if (error) throw error;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const env = loadEnv();
  await ensureDatabase(env.DATABASE_URL);
  const db = createDb(env.DATABASE_URL);
  try { await migrateToLatest(db); console.log('Database is up to date.'); } finally { await db.destroy(); }
}
