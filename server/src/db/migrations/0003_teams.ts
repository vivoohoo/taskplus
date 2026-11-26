// Ornate's organisation (docs/PARITY.md): teams inside departments, each with a team lead; leads report upward
// (Vishwas -> Dhaval -> Tushar). A department chat can be addressed to one team.
import { sql, type Kysely } from 'kysely';

export async function up(db: Kysely<unknown>) {
  await sql`
CREATE TABLE teams (
  id uniqueidentifier NOT NULL CONSTRAINT PK_teams PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
  department_id uniqueidentifier NOT NULL CONSTRAINT FK_teams_department REFERENCES departments(id),
  name nvarchar(80) NOT NULL,
  lead_id uniqueidentifier NULL CONSTRAINT FK_teams_lead REFERENCES users(id),
  created_at datetimeoffset(3) NOT NULL DEFAULT SYSDATETIMEOFFSET(),
  CONSTRAINT UQ_teams_name UNIQUE (department_id, name)
);
ALTER TABLE users ADD
  team_id uniqueidentifier NULL CONSTRAINT FK_users_team REFERENCES teams(id),
  reports_to_id uniqueidentifier NULL CONSTRAINT FK_users_reports_to REFERENCES users(id);
ALTER TABLE users DROP CONSTRAINT CK_users_role;
ALTER TABLE users ADD CONSTRAINT CK_users_role CHECK (role IN ('staff', 'team_lead', 'dept_head', 'admin'));
ALTER TABLE threads ADD team_id uniqueidentifier NULL CONSTRAINT FK_threads_team REFERENCES teams(id);
ALTER TABLE tasks ADD team_id uniqueidentifier NULL CONSTRAINT FK_tasks_team REFERENCES teams(id);
DROP INDEX UX_threads_department ON threads;
`.execute(db);
  // A department chat per (requester, department, team); team NULL = the whole department.
  await sql`CREATE UNIQUE INDEX UX_threads_department ON threads(requester_id, department_id, team_id) WHERE type = 'department'`.execute(db);
  await sql`CREATE INDEX IX_tasks_team_status ON tasks(team_id, status)`.execute(db);
}

export async function down(db: Kysely<unknown>) {
  await sql`
DROP INDEX IX_tasks_team_status ON tasks;
DROP INDEX UX_threads_department ON threads;
ALTER TABLE tasks DROP CONSTRAINT FK_tasks_team; ALTER TABLE tasks DROP COLUMN team_id;
ALTER TABLE threads DROP CONSTRAINT FK_threads_team; ALTER TABLE threads DROP COLUMN team_id;
ALTER TABLE users DROP CONSTRAINT CK_users_role;
ALTER TABLE users ADD CONSTRAINT CK_users_role CHECK (role IN ('staff', 'dept_head', 'admin'));
ALTER TABLE users DROP CONSTRAINT FK_users_team, FK_users_reports_to; ALTER TABLE users DROP COLUMN team_id, reports_to_id;
DROP TABLE teams;
CREATE UNIQUE INDEX UX_threads_department ON threads(requester_id, department_id) WHERE type = 'department';
`.execute(db);
}
