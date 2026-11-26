// Phase 1 tables (spec §6), in SQL Server. UUID keys, datetimeoffset stamps, JSON kept as nvarchar(max) with ISJSON checks.
import { sql, type Kysely } from 'kysely';

export async function up(db: Kysely<unknown>) {
  await sql`
CREATE TABLE departments (
  id uniqueidentifier NOT NULL CONSTRAINT PK_departments PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
  name nvarchar(80) NOT NULL CONSTRAINT UQ_departments_name UNIQUE,
  head_user_id uniqueidentifier NULL,
  modules nvarchar(max) NOT NULL DEFAULT '[]' CONSTRAINT CK_departments_modules CHECK (ISJSON(modules) = 1),
  created_at datetimeoffset(3) NOT NULL DEFAULT SYSDATETIMEOFFSET(),
  updated_at datetimeoffset(3) NOT NULL DEFAULT SYSDATETIMEOFFSET()
);

CREATE TABLE users (
  id uniqueidentifier NOT NULL CONSTRAINT PK_users PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
  name nvarchar(100) NOT NULL,
  phone varchar(15) NOT NULL CONSTRAINT UQ_users_phone UNIQUE,
  email nvarchar(200) NULL,
  role varchar(10) NOT NULL CONSTRAINT CK_users_role CHECK (role IN ('staff', 'dept_head', 'admin')),
  department_id uniqueidentifier NULL CONSTRAINT FK_users_department REFERENCES departments(id),
  avatar_url nvarchar(400) NULL,
  is_active bit NOT NULL DEFAULT 1,
  created_at datetimeoffset(3) NOT NULL DEFAULT SYSDATETIMEOFFSET(),
  updated_at datetimeoffset(3) NOT NULL DEFAULT SYSDATETIMEOFFSET()
);
ALTER TABLE departments ADD CONSTRAINT FK_departments_head FOREIGN KEY (head_user_id) REFERENCES users(id);

CREATE TABLE device_tokens (
  id uniqueidentifier NOT NULL CONSTRAINT PK_device_tokens PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
  user_id uniqueidentifier NOT NULL CONSTRAINT FK_device_tokens_user REFERENCES users(id),
  fcm_token varchar(400) NOT NULL CONSTRAINT UQ_device_tokens_token UNIQUE,
  platform varchar(8) NOT NULL CONSTRAINT CK_device_tokens_platform CHECK (platform IN ('android', 'ios')),
  last_seen_at datetimeoffset(3) NOT NULL DEFAULT SYSDATETIMEOFFSET()
);

CREATE TABLE threads (
  id uniqueidentifier NOT NULL CONSTRAINT PK_threads PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
  type varchar(10) NOT NULL CONSTRAINT CK_threads_type CHECK (type IN ('direct', 'department')),
  user_a_id uniqueidentifier NULL CONSTRAINT FK_threads_user_a REFERENCES users(id),
  user_b_id uniqueidentifier NULL CONSTRAINT FK_threads_user_b REFERENCES users(id),
  requester_id uniqueidentifier NULL CONSTRAINT FK_threads_requester REFERENCES users(id),
  department_id uniqueidentifier NULL CONSTRAINT FK_threads_department REFERENCES departments(id),
  last_message_at datetimeoffset(3) NULL,
  created_at datetimeoffset(3) NOT NULL DEFAULT SYSDATETIMEOFFSET(),
  updated_at datetimeoffset(3) NOT NULL DEFAULT SYSDATETIMEOFFSET(),
  CONSTRAINT CK_threads_shape CHECK (
    (type = 'direct' AND user_a_id IS NOT NULL AND user_b_id IS NOT NULL AND user_a_id <> user_b_id AND requester_id IS NULL AND department_id IS NULL)
    OR (type = 'department' AND requester_id IS NOT NULL AND department_id IS NOT NULL AND user_a_id IS NULL AND user_b_id IS NULL))
);
CREATE UNIQUE INDEX UX_threads_direct ON threads(user_a_id, user_b_id) WHERE type = 'direct';
CREATE UNIQUE INDEX UX_threads_department ON threads(requester_id, department_id) WHERE type = 'department';

CREATE TABLE messages (
  id uniqueidentifier NOT NULL CONSTRAINT PK_messages PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
  thread_id uniqueidentifier NOT NULL CONSTRAINT FK_messages_thread REFERENCES threads(id),
  sender_id uniqueidentifier NOT NULL CONSTRAINT FK_messages_sender REFERENCES users(id),
  client_msg_id uniqueidentifier NOT NULL,
  kind varchar(10) NOT NULL CONSTRAINT CK_messages_kind CHECK (kind IN ('text', 'voice', 'attachment')),
  body_text nvarchar(4000) NULL,
  audio_key varchar(300) NULL,
  audio_duration_s int NULL CONSTRAINT CK_messages_audio CHECK (audio_duration_s BETWEEN 0 AND 180),
  transcript nvarchar(max) NULL,
  transcript_lang varchar(10) NULL,
  created_at datetimeoffset(3) NOT NULL DEFAULT SYSDATETIMEOFFSET()
);
CREATE UNIQUE INDEX UX_messages_client ON messages(sender_id, client_msg_id);
CREATE INDEX IX_messages_thread ON messages(thread_id, created_at DESC);

CREATE TABLE attachments (
  id uniqueidentifier NOT NULL CONSTRAINT PK_attachments PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
  message_id uniqueidentifier NOT NULL CONSTRAINT FK_attachments_message REFERENCES messages(id),
  r2_key varchar(300) NOT NULL,
  mime varchar(100) NOT NULL,
  size_bytes int NOT NULL CONSTRAINT CK_attachments_size CHECK (size_bytes BETWEEN 1 AND 10485760),
  width int NULL,
  height int NULL
);

CREATE TABLE tasks (
  id uniqueidentifier NOT NULL CONSTRAINT PK_tasks PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
  message_id uniqueidentifier NOT NULL CONSTRAINT FK_tasks_message REFERENCES messages(id),
  thread_id uniqueidentifier NOT NULL CONSTRAINT FK_tasks_thread REFERENCES threads(id),
  source varchar(10) NOT NULL DEFAULT 'app' CONSTRAINT CK_tasks_source CHECK (source IN ('app', 'email', 'whatsapp')),
  subject nvarchar(60) NULL,
  module nvarchar(80) NULL,
  customer_name nvarchar(150) NULL,
  customer_phone varchar(15) NULL,
  customer_location nvarchar(150) NULL,
  license_no nvarchar(60) NULL,
  priority varchar(6) NOT NULL CONSTRAINT CK_tasks_priority CHECK (priority IN ('High', 'Medium', 'Low')),
  details nvarchar(max) NULL,
  status varchar(10) NOT NULL DEFAULT 'Open' CONSTRAINT CK_tasks_status CHECK (status IN ('Open', 'Accepted', 'InProgress', 'Closed')),
  assignee_id uniqueidentifier NULL CONSTRAINT FK_tasks_assignee REFERENCES users(id),
  tagged_user_id uniqueidentifier NULL CONSTRAINT FK_tasks_tagged REFERENCES users(id),
  department_id uniqueidentifier NULL CONSTRAINT FK_tasks_department REFERENCES departments(id),
  ai_status varchar(12) NOT NULL DEFAULT 'pending' CONSTRAINT CK_tasks_ai CHECK (ai_status IN ('pending', 'done', 'needs_review')),
  ai_error nvarchar(400) NULL,
  ai_provider varchar(20) NULL,
  prompt_version varchar(20) NULL,
  overrides nvarchar(max) NOT NULL DEFAULT '{}' CONSTRAINT CK_tasks_overrides CHECK (ISJSON(overrides) = 1),
  due_at datetimeoffset(3) NOT NULL,
  closed_at datetimeoffset(3) NULL,
  created_at datetimeoffset(3) NOT NULL DEFAULT SYSDATETIMEOFFSET(),
  updated_at datetimeoffset(3) NOT NULL DEFAULT SYSDATETIMEOFFSET()
);
-- One task per message in Phase 1. Drop this index to allow several.
CREATE UNIQUE INDEX UX_tasks_message ON tasks(message_id);
CREATE INDEX IX_tasks_department_status ON tasks(department_id, status);
CREATE INDEX IX_tasks_assignee_status ON tasks(assignee_id, status);
CREATE INDEX IX_tasks_due_open ON tasks(due_at) WHERE status <> 'Closed';

CREATE TABLE task_events (
  id uniqueidentifier NOT NULL CONSTRAINT PK_task_events PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
  task_id uniqueidentifier NOT NULL CONSTRAINT FK_task_events_task REFERENCES tasks(id),
  actor_id uniqueidentifier NULL CONSTRAINT FK_task_events_actor REFERENCES users(id),
  type varchar(16) NOT NULL CONSTRAINT CK_task_events_type
    CHECK (type IN ('created', 'structured', 'accepted', 'reassigned', 'status_changed', 'closed')),
  payload nvarchar(max) NOT NULL DEFAULT '{}' CONSTRAINT CK_task_events_payload CHECK (ISJSON(payload) = 1),
  created_at datetimeoffset(3) NOT NULL DEFAULT SYSDATETIMEOFFSET()
);
CREATE INDEX IX_task_events_task ON task_events(task_id, created_at);
`.execute(db);
}

export async function down(db: Kysely<unknown>) {
  await sql`
ALTER TABLE departments DROP CONSTRAINT FK_departments_head;
DROP TABLE task_events; DROP TABLE tasks; DROP TABLE attachments; DROP TABLE messages;
DROP TABLE threads; DROP TABLE device_tokens; DROP TABLE users; DROP TABLE departments;
`.execute(db);
}
