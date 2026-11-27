// Ornate look and basics (docs/ORNATE_UI.md): private notes (a chat with yourself), sub-tasks to another department
// (parent waits in WaitingDept), and the in-app notification list behind the bell.
import { sql, type Kysely } from 'kysely';

export const STATUSES = ['Open', 'Accepted', 'InProgress', 'WaitingInfo', 'WaitingDept', 'Blocked', 'Completed', 'Verified', 'Closed', 'Rejected', 'Transferred', 'Cancelled'] as const;
export const EVENT_TYPES = ['created', 'structured', 'accepted', 'reassigned', 'status_changed', 'closed',
  'cancelled', 'edited', 'assigned', 'declined', 'reassign_asked', 'reassign_refused', 'completed', 'verified', 'reopened', 'question', 'answered',
  'blocked', 'unblocked', 'request', 'request_refused', 'rejected', 'transferred', 'escalated', 'attended', 'priority_changed', 'warned',
  'handed_off', 'subtask_done', 'subs_cancelled'] as const;
const list = (xs: readonly string[]) => sql.raw(xs.map((x) => `'${x}'`).join(', '));

export async function up(db: Kysely<unknown>) {
  await sql`
ALTER TABLE threads DROP CONSTRAINT CK_threads_type;
ALTER TABLE threads DROP CONSTRAINT CK_threads_shape;
ALTER TABLE threads ADD CONSTRAINT CK_threads_type CHECK (type IN ('direct', 'department', 'self'));
ALTER TABLE threads ADD CONSTRAINT CK_threads_shape CHECK (
    (type = 'direct' AND user_a_id IS NOT NULL AND user_b_id IS NOT NULL AND user_a_id <> user_b_id AND requester_id IS NULL AND department_id IS NULL)
    OR (type = 'department' AND requester_id IS NOT NULL AND department_id IS NOT NULL AND user_a_id IS NULL AND user_b_id IS NULL)
    OR (type = 'self' AND requester_id IS NOT NULL AND department_id IS NULL AND user_a_id IS NULL AND user_b_id IS NULL));
ALTER TABLE tasks ADD parent_task_id uniqueidentifier NULL CONSTRAINT FK_tasks_parent REFERENCES tasks(id);
ALTER TABLE tasks DROP CONSTRAINT CK_tasks_status;
ALTER TABLE tasks ADD CONSTRAINT CK_tasks_status CHECK (status IN (${list(STATUSES)}));
ALTER TABLE task_events DROP CONSTRAINT CK_task_events_type;
ALTER TABLE task_events ADD CONSTRAINT CK_task_events_type CHECK (type IN (${list(EVENT_TYPES)}));
CREATE TABLE notifications (
  id uniqueidentifier NOT NULL CONSTRAINT PK_notifications PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
  user_id uniqueidentifier NOT NULL CONSTRAINT FK_notifications_user REFERENCES users(id),
  task_id uniqueidentifier NOT NULL CONSTRAINT FK_notifications_task REFERENCES tasks(id),
  text nvarchar(300) NOT NULL,
  read_at datetimeoffset(3) NULL,
  created_at datetimeoffset(3) NOT NULL DEFAULT SYSDATETIMEOFFSET()
);
`.execute(db);
  await sql`
CREATE UNIQUE INDEX UX_threads_self ON threads(requester_id) WHERE type = 'self';
CREATE INDEX IX_tasks_parent ON tasks(parent_task_id) WHERE parent_task_id IS NOT NULL;
CREATE INDEX IX_notifications_user ON notifications(user_id, created_at DESC);
`.execute(db);
}

export async function down(db: Kysely<unknown>) {
  await sql`
DROP TABLE notifications;
DROP INDEX IX_tasks_parent ON tasks;
DROP INDEX UX_threads_self ON threads;
ALTER TABLE tasks DROP CONSTRAINT FK_tasks_parent;
ALTER TABLE tasks DROP COLUMN parent_task_id;
`.execute(db);
}
