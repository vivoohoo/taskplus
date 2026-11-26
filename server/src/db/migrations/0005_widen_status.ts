// The first schema sized status for "InProgress" (10) and priority for "Medium" (6); "WaitingInfo", "Transferred"
// and "Critical" need more. SQL Server needs the checks and indexes on a column dropped before it can be widened.
import { sql, type Kysely } from 'kysely';
import { PRIORITIES, STATUSES } from './0002_passwords_statuses';

const list = (xs: readonly string[]) => sql.raw(xs.map((x) => `'${x}'`).join(', '));

export async function up(db: Kysely<unknown>) {
  await sql`
DROP INDEX IX_tasks_department_status ON tasks;
DROP INDEX IX_tasks_assignee_status ON tasks;
DROP INDEX IX_tasks_due_open ON tasks;
DROP INDEX IX_tasks_team_status ON tasks;
ALTER TABLE tasks DROP CONSTRAINT CK_tasks_status;
ALTER TABLE tasks DROP CONSTRAINT CK_tasks_priority;
DECLARE @df sysname = (SELECT name FROM sys.default_constraints WHERE parent_object_id = OBJECT_ID('tasks') AND parent_column_id = COLUMNPROPERTY(OBJECT_ID('tasks'), 'status', 'ColumnId'));
IF @df IS NOT NULL EXEC('ALTER TABLE tasks DROP CONSTRAINT ' + @df);
ALTER TABLE tasks ALTER COLUMN status varchar(16) NOT NULL;
ALTER TABLE tasks ALTER COLUMN priority varchar(10) NOT NULL;
ALTER TABLE tasks ADD CONSTRAINT DF_tasks_status DEFAULT 'Open' FOR status;
`.execute(db);
  await sql`
ALTER TABLE tasks ADD CONSTRAINT CK_tasks_status CHECK (status IN (${list(STATUSES)}));
ALTER TABLE tasks ADD CONSTRAINT CK_tasks_priority CHECK (priority IN (${list(PRIORITIES)}));
CREATE INDEX IX_tasks_department_status ON tasks(department_id, status);
CREATE INDEX IX_tasks_assignee_status ON tasks(assignee_id, status);
CREATE INDEX IX_tasks_team_status ON tasks(team_id, status);
CREATE INDEX IX_tasks_due_open ON tasks(due_at) WHERE status <> 'Closed';
`.execute(db);
}

export async function down() { /* widening is harmless to keep */ }
