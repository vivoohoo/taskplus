// Ornate's core workflow and working-hours clock (docs/PARITY.md, step 3).
import { sql, type Kysely } from 'kysely';

export async function up(db: Kysely<unknown>) {
  await sql`
ALTER TABLE users ADD
  shift tinyint NOT NULL CONSTRAINT DF_users_shift DEFAULT 0,   -- 0 = 9-6, 1 = 10-7, 2 = 11-8 (Mon-Sat)
  away bit NOT NULL CONSTRAINT DF_users_away DEFAULT 0;
CREATE TABLE holidays (
  day date NOT NULL CONSTRAINT PK_holidays PRIMARY KEY,
  name nvarchar(80) NULL
);
ALTER TABLE tasks ADD
  clock_state varchar(12) NOT NULL CONSTRAINT DF_tasks_clock DEFAULT 'not started'
    CONSTRAINT CK_tasks_clock CHECK (clock_state IN ('not started', 'running', 'paused', 'stopped')),
  clock_used_ms bigint NOT NULL CONSTRAINT DF_tasks_used DEFAULT 0,
  clock_running_since datetimeoffset(3) NULL,
  used_before_transfer bigint NULL,
  queued_at datetimeoffset(3) NULL,               -- accept time counts from here
  accepted_at datetimeoffset(3) NULL,
  completed_at datetimeoffset(3) NULL,
  verified_at datetimeoffset(3) NULL,
  resolution nvarchar(2000) NULL,
  customer_informed varchar(3) NULL CONSTRAINT CK_tasks_informed CHECK (customer_informed IN ('yes', 'no', 'n/a')),
  escalation_level varchar(16) NULL CONSTRAINT CK_tasks_esc CHECK (escalation_level IN ('team_lead', 'dept_head', 'management')),
  escalated_to nvarchar(400) NOT NULL CONSTRAINT DF_tasks_escto DEFAULT '[]',
  auto_escalated_at datetimeoffset(3) NULL,
  head_alerted bit NOT NULL CONSTRAINT DF_tasks_headal DEFAULT 0,
  reassign_requested_by uniqueidentifier NULL,
  reassign_asked nvarchar(1000) NOT NULL CONSTRAINT DF_tasks_rasked DEFAULT '{}', -- userId -> ISO time (once a day)
  declined_by nvarchar(1000) NOT NULL CONSTRAINT DF_tasks_declined DEFAULT '[]',
  request nvarchar(1000) NULL,                    -- staff asking to reject/transfer: { kind, by, reason, departmentId }
  warned nvarchar(100) NOT NULL CONSTRAINT DF_tasks_warned DEFAULT '[]',
  transferred_from_id uniqueidentifier NULL CONSTRAINT FK_tasks_transferred_from REFERENCES tasks(id);
ALTER TABLE messages ADD reply_to_task_id uniqueidentifier NULL CONSTRAINT FK_messages_reply REFERENCES tasks(id);
`.execute(db);
  await sql`UPDATE tasks SET queued_at = created_at`.execute(db);
  await sql`INSERT INTO holidays (day, name) VALUES ('2026-01-26', 'Republic Day'), ('2026-08-15', 'Independence Day'),
    ('2026-10-02', 'Gandhi Jayanti'), ('2026-12-25', 'Christmas'), ('2027-01-26', 'Republic Day')`.execute(db);
}

export async function down(db: Kysely<unknown>) {
  await sql`
ALTER TABLE messages DROP CONSTRAINT FK_messages_reply; ALTER TABLE messages DROP COLUMN reply_to_task_id;
ALTER TABLE tasks DROP CONSTRAINT FK_tasks_transferred_from, CK_tasks_clock, DF_tasks_clock, DF_tasks_used, CK_tasks_informed, CK_tasks_esc,
  DF_tasks_escto, DF_tasks_headal, DF_tasks_rasked, DF_tasks_declined, DF_tasks_warned;
ALTER TABLE tasks DROP COLUMN clock_state, clock_used_ms, clock_running_since, used_before_transfer, queued_at, accepted_at, completed_at, verified_at,
  resolution, customer_informed, escalation_level, escalated_to, auto_escalated_at, head_alerted, reassign_requested_by, reassign_asked, declined_by,
  request, warned, transferred_from_id;
DROP TABLE holidays;
ALTER TABLE users DROP CONSTRAINT DF_users_shift, DF_users_away; ALTER TABLE users DROP COLUMN shift, away;
`.execute(db);
}
