// A real SQL Server for integration tests: TEST_DATABASE_URL if set, otherwise a throwaway Testcontainers container.
import { MSSQLServerContainer, type StartedMSSQLServerContainer } from '@testcontainers/mssqlserver';
import { createDb, type Db } from '../../src/db/client';
import { ensureDatabase, migrateToLatest } from '../../src/db/migrate';
import { seed } from '../../src/db/seed';

let container: StartedMSSQLServerContainer | undefined;

export async function startTestDb(): Promise<{ url: string; db: Db; stop: () => Promise<void> }> {
  let url = process.env.TEST_DATABASE_URL;
  if (!url) {
    container = await new MSSQLServerContainer('mcr.microsoft.com/mssql/server:2022-latest').acceptLicense().start();
    url = `mssql://sa:${encodeURIComponent(container.getPassword())}@${container.getHost()}:${container.getPort()}/taskplus_test?trustServerCertificate=true`;
  }
  await ensureDatabase(url);
  const db = createDb(url);
  await migrateToLatest(db);
  await seed(db);
  return { url, db, stop: async () => { await db.destroy(); await container?.stop(); } };
}
