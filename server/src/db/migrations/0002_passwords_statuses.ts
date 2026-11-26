// Own-password sign-in (D7), and the full status/priority lists for the Ornate workflow (docs/PARITY.md).
import { sql, type Kysely } from 'kysely';

export const STATUSES = ['Open', 'Accepted', 'InProgress', 'WaitingInfo', 'Blocked', 'Completed', 'Verified', 'Closed', 'Rejected', 'Transferred', 'Cancelled'] as const;
export const PRIORITIES = ['Critical', 'High', 'Medium', 'Low'] as const;
const list = (xs: readonly string[]) => sql.raw(xs.map((x) => `'${x}'`).join(', '));

export async function up(db: Kysely<unknown>) {
  await sql`
ALTER TABLE users ADD
  password_hash varbinary(64) NULL,
  password_salt varbinary(16) NULL,
  failed_logins int NOT NULL CONSTRAINT DF_users_failed DEFAULT 0,
  locked_until datetimeoffset(3) NULL;
ALTER TABLE tasks DROP CONSTRAINT CK_tasks_status;
ALTER TABLE tasks ADD CONSTRAINT CK_tasks_status CHECK (status IN (${list(STATUSES)}));
ALTER TABLE tasks DROP CONSTRAINT CK_tasks_priority;
ALTER TABLE tasks ADD CONSTRAINT CK_tasks_priority CHECK (priority IN (${list(PRIORITIES)}));
ALTER TABLE task_events DROP CONSTRAINT CK_task_events_type;
ALTER TABLE task_events ADD CONSTRAINT CK_task_events_type CHECK (type IN ('created', 'structured', 'accepted', 'reassigned', 'status_changed', 'closed',
  'cancelled', 'edited', 'assigned', 'declined', 'reassign_asked', 'reassign_refused', 'completed', 'verified', 'reopened', 'question', 'answered',
  'blocked', 'unblocked', 'request', 'request_refused', 'rejected', 'transferred', 'escalated', 'attended', 'priority_changed', 'warned'));
`.execute(db);
}

export async function down(db: Kysely<unknown>) {
  await sql`
ALTER TABLE task_events DROP CONSTRAINT CK_task_events_type;
ALTER TABLE task_events ADD CONSTRAINT CK_task_events_type CHECK (type IN ('created', 'structured', 'accepted', 'reassigned', 'status_changed', 'closed'));
ALTER TABLE tasks DROP CONSTRAINT CK_tasks_priority;
ALTER TABLE tasks ADD CONSTRAINT CK_tasks_priority CHECK (priority IN ('High', 'Medium', 'Low'));
ALTER TABLE tasks DROP CONSTRAINT CK_tasks_status;
ALTER TABLE tasks ADD CONSTRAINT CK_tasks_status CHECK (status IN ('Open', 'Accepted', 'InProgress', 'Closed'));
ALTER TABLE users DROP CONSTRAINT DF_users_failed;
ALTER TABLE users DROP COLUMN password_hash, password_salt, failed_logins, locked_until;
`.execute(db);
}
