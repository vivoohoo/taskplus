// Step 4 (docs/PARITY.md): ticket numbers, muted alerts, suggestions, customers.
import { sql, type Kysely } from 'kysely';

export async function up(db: Kysely<unknown>) {
  await sql`
ALTER TABLE tasks ADD ticket_no varchar(30) NULL;
ALTER TABLE users ADD muted_kinds nvarchar(400) NOT NULL CONSTRAINT DF_users_muted DEFAULT '[]';
CREATE TABLE ticket_counters (
  prefix varchar(20) NOT NULL CONSTRAINT PK_ticket_counters PRIMARY KEY,
  last_no int NOT NULL
);
CREATE TABLE suggestions (
  id uniqueidentifier NOT NULL CONSTRAINT PK_suggestions PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
  by_id uniqueidentifier NOT NULL CONSTRAINT FK_suggestions_by REFERENCES users(id),
  text nvarchar(2000) NOT NULL,
  status varchar(12) NOT NULL CONSTRAINT DF_suggestions_status DEFAULT 'New'
    CONSTRAINT CK_suggestions_status CHECK (status IN ('New', 'Seen', 'Planned', 'Done', 'Not planned')),
  created_at datetimeoffset(3) NOT NULL DEFAULT SYSDATETIMEOFFSET()
);
CREATE TABLE customers (
  id uniqueidentifier NOT NULL CONSTRAINT PK_customers PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
  name nvarchar(150) NOT NULL CONSTRAINT UQ_customers_name UNIQUE,
  active bit NOT NULL CONSTRAINT DF_customers_active DEFAULT 1
);
`.execute(db);
  await sql`CREATE UNIQUE INDEX UX_tasks_ticket ON tasks(ticket_no) WHERE ticket_no IS NOT NULL`.execute(db);
  // Number the tasks that already exist, oldest first, within their financial year.
  await sql`
WITH n AS (
  SELECT id, 'ORN-SS-' + RIGHT(CAST(fy AS varchar(4)), 2) + RIGHT(CAST(fy + 1 AS varchar(4)), 2) + '-' AS prefix,
         ROW_NUMBER() OVER (PARTITION BY fy ORDER BY created_at, id) AS rn
  FROM (SELECT id, created_at, CASE WHEN MONTH(SWITCHOFFSET(created_at, '+05:30')) >= 4 THEN YEAR(SWITCHOFFSET(created_at, '+05:30'))
                                    ELSE YEAR(SWITCHOFFSET(created_at, '+05:30')) - 1 END AS fy FROM tasks) x
)
UPDATE t SET ticket_no = n.prefix + RIGHT('00000' + CAST(n.rn AS varchar(10)), 5) FROM tasks t JOIN n ON n.id = t.id;
INSERT INTO ticket_counters (prefix, last_no)
  SELECT LEFT(ticket_no, 12), MAX(CAST(RIGHT(ticket_no, 5) AS int)) FROM tasks WHERE ticket_no IS NOT NULL GROUP BY LEFT(ticket_no, 12);
INSERT INTO customers (name) VALUES ('Mehta Traders'), ('Shree Ganesh Textiles'), ('Sunrise Pharma'), ('Om Logistics'), ('Patel Agro Foods'), ('Kaveri Steel');
`.execute(db);
}

export async function down(db: Kysely<unknown>) {
  await sql`
DROP INDEX UX_tasks_ticket ON tasks; ALTER TABLE tasks DROP COLUMN ticket_no;
ALTER TABLE users DROP CONSTRAINT DF_users_muted; ALTER TABLE users DROP COLUMN muted_kinds;
DROP TABLE ticket_counters; DROP TABLE suggestions; DROP TABLE customers;
`.execute(db);
}
