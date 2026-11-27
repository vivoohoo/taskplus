// The browser demo's shared data (Vercel function + Postgres from Supabase or Neon).
// GET    -> { version, data }            the latest demo data (data null until the first save)
// PUT    { version, data } -> { version } saves if nobody saved in between, else 409 with the latest
// DELETE -> { ok }                       back to the sample data
// Sample data only: no sign-in, anyone with the link can change it.
const postgres = require('postgres');

const url = process.env.POSTGRES_URL || process.env.DATABASE_URL || process.env.POSTGRES_PRISMA_URL;
// Hosted Postgres (Supabase, Neon) needs TLS; a local test database doesn't.
const sql = url ? postgres(url, { ssl: /@(localhost|127.0.0.1)[:/]/.test(url) ? false : 'require', max: 1, prepare: false }) : null;
let ready = false;

async function table() {
  if (ready) return;
  await sql`CREATE TABLE IF NOT EXISTS taskplus_demo (id int PRIMARY KEY, version int NOT NULL, data jsonb NOT NULL, updated_at timestamptz NOT NULL DEFAULT now())`;
  ready = true;
}

module.exports = async (req, res) => {
  res.setHeader('cache-control', 'no-store');
  if (!sql) return res.status(503).json({ error: 'No database connected. Add Supabase or Neon in Vercel > Storage.' });
  try {
    await table();
    if (req.method === 'GET') {
      const [row] = await sql`SELECT version, data FROM taskplus_demo WHERE id = 1`;
      return res.status(200).json(row ? { version: row.version, data: row.data } : { version: 0, data: null });
    }
    if (req.method === 'PUT') {
      const body = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
      if (!body || typeof body.version !== 'number' || typeof body.data !== 'object') return res.status(400).json({ error: 'Send { version, data }.' });
      if (JSON.stringify(body.data).length > 4_000_000) return res.status(413).json({ error: 'Too much data.' });
      const next = body.version + 1;
      // Saved only if the stored version is still the one this browser loaded (or nothing is stored yet).
      const rows = body.version === 0
        ? await sql`INSERT INTO taskplus_demo (id, version, data) VALUES (1, 1, ${sql.json(body.data)}) ON CONFLICT (id) DO NOTHING RETURNING version`
        : await sql`UPDATE taskplus_demo SET version = ${next}, data = ${sql.json(body.data)}, updated_at = now() WHERE id = 1 AND version = ${body.version} RETURNING version`;
      if (rows.length) return res.status(200).json({ version: rows[0].version });
      const [row] = await sql`SELECT version, data FROM taskplus_demo WHERE id = 1`;
      return res.status(409).json({ version: row.version, data: row.data });
    }
    if (req.method === 'DELETE') {
      await sql`DELETE FROM taskplus_demo WHERE id = 1`;
      return res.status(200).json({ ok: true });
    }
    return res.status(405).json({ error: 'GET, PUT or DELETE.' });
  } catch (e) {
    return res.status(500).json({ error: String(e && e.message || e) });
  }
};
