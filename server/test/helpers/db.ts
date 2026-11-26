// A fresh SQL Server database per test file: on TEST_DATABASE_URL's server if set, otherwise in a Testcontainers container.
import { MSSQLServerContainer, type StartedMSSQLServerContainer } from '@testcontainers/mssqlserver';
import { sql } from 'kysely';
import { createDb, type Db } from '../../src/db/client';
import { ensureDatabase, migrateToLatest } from '../../src/db/migrate';
import { seed } from '../../src/db/seed';

export const TEST_PASSWORD = 'Test@1234';

export async function startTestDb(): Promise<{ url: string; db: Db; stop: () => Promise<void> }> {
  let container: StartedMSSQLServerContainer | undefined;
  let base = process.env.TEST_DATABASE_URL;
  if (!base) {
    container = await new MSSQLServerContainer('mcr.microsoft.com/mssql/server:2022-latest').acceptLicense().start();
    base = `mssql://sa:${encodeURIComponent(container.getPassword())}@${container.getHost()}:${container.getPort()}/master?trustServerCertificate=true`;
  }
  const u = new URL(base);
  const name = `taskplus_test_${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
  u.pathname = `/${name}`;
  const url = u.toString();
  await ensureDatabase(url);
  const db = createDb(url);
  await migrateToLatest(db);
  await seed(db, TEST_PASSWORD);
  return {
    url, db,
    stop: async () => {
      await db.destroy();
      if (container) { await container.stop(); return; }
      u.pathname = '/master';
      const master = createDb(u.toString());
      try { await sql.raw(`ALTER DATABASE [${name}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [${name}]`).execute(master); } finally { await master.destroy(); }
    },
  };
}
