// Ticket numbers like Ornate's: ORN-SS-2627-00042, restarting at 00001 every April (financial year, India time).
// The counter row is locked inside the caller's transaction, so two tasks can never get the same number.
import { sql, type Transaction } from 'kysely';
import type { Database } from '../db/schema';

export function ticketPrefix(now: Date) {
  const ist = new Date(now.getTime() + 5.5 * 3600_000);
  const fy = ist.getUTCMonth() >= 3 ? ist.getUTCFullYear() : ist.getUTCFullYear() - 1;
  const yy = (y: number) => String(y % 100).padStart(2, '0');
  return `ORN-SS-${yy(fy)}${yy(fy + 1)}-`;
}

export async function nextTicketNo(tx: Transaction<Database>, now = new Date()) {
  const prefix = ticketPrefix(now);
  const r = await sql<{ last_no: number }>`
MERGE ticket_counters WITH (HOLDLOCK) AS c
USING (SELECT ${prefix} AS prefix) AS s ON c.prefix = s.prefix
WHEN MATCHED THEN UPDATE SET last_no = c.last_no + 1
WHEN NOT MATCHED THEN INSERT (prefix, last_no) VALUES (s.prefix, 1)
OUTPUT inserted.last_no;`.execute(tx);
  return prefix + String(r.rows[0]!.last_no).padStart(5, '0');
}
