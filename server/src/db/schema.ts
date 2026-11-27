// Table types for Kysely. The tables themselves are created by db/migrations (SQL Server).
import type { ColumnType, Generated, Insertable, Selectable, Updateable } from 'kysely';

type Id = Generated<string>; // uniqueidentifier, NEWSEQUENTIALID()
type Stamp = ColumnType<Date, Date | undefined, Date>; // datetimeoffset, defaults to now
type Json<T> = ColumnType<T, string, string>; // stored as nvarchar(max) JSON text

export type Role = 'staff' | 'team_lead' | 'dept_head' | 'admin';
export type Priority = 'Critical' | 'High' | 'Medium' | 'Low';
export type TaskStatus = 'Open' | 'Accepted' | 'InProgress' | 'WaitingInfo' | 'WaitingDept' | 'Blocked' | 'Completed' | 'Verified' | 'Closed' | 'Rejected' | 'Transferred' | 'Cancelled';
export type AiStatus = 'pending' | 'done' | 'needs_review';
export type MessageKind = 'text' | 'voice' | 'attachment';
export type TaskEventType = 'created' | 'structured' | 'accepted' | 'reassigned' | 'status_changed' | 'closed'
  | 'cancelled' | 'edited' | 'assigned' | 'declined' | 'reassign_asked' | 'reassign_refused' | 'completed' | 'verified' | 'reopened'
  | 'question' | 'answered' | 'blocked' | 'unblocked' | 'request' | 'request_refused' | 'rejected' | 'transferred' | 'escalated' | 'attended'
  | 'priority_changed' | 'warned' | 'handed_off' | 'subtask_done' | 'subs_cancelled';

export type ClockState = 'not started' | 'running' | 'paused' | 'stopped';
export type EscalationLevel = 'team_lead' | 'dept_head' | 'management';

export interface Overrides { priority?: Priority; customer?: string; license?: string; module?: string }

export interface Database {
  departments: { id: Id; name: string; head_user_id: string | null; modules: Json<string[]>; created_at: Stamp; updated_at: Stamp };
  users: {
    id: Id; name: string; phone: string; email: string | null; role: Role; department_id: string | null;
    avatar_url: string | null; is_active: Generated<boolean>; created_at: Stamp; updated_at: Stamp;
    password_hash: Buffer | null; password_salt: Buffer | null; failed_logins: Generated<number>; locked_until: Date | null;
    team_id: Generated<string | null>; reports_to_id: Generated<string | null>;
    shift: Generated<number>; away: Generated<boolean>; muted_kinds: Generated<string>;
  };
  ticket_counters: { prefix: string; last_no: number };
  suggestions: { id: Id; by_id: string; text: string; status: Generated<'New' | 'Seen' | 'Planned' | 'Done' | 'Not planned'>; created_at: Stamp };
  customers: { id: Id; name: string; active: Generated<boolean> };
  holidays: { day: Date; name: string | null };
  teams: { id: Id; department_id: string; name: string; lead_id: string | null; created_at: Stamp };
  device_tokens: { id: Id; user_id: string; fcm_token: string; platform: 'android' | 'ios'; last_seen_at: Stamp };
  threads: {
    id: Id; type: 'direct' | 'department' | 'self';                 // self: private notes
    user_a_id: string | null; user_b_id: string | null;       // direct: sorted pair
    requester_id: string | null; department_id: string | null; // department
    team_id: Generated<string | null>;                          // department chat addressed to one team
    last_message_at: Date | null; created_at: Stamp; updated_at: Stamp;
  };
  messages: {
    id: Id; thread_id: string; sender_id: string; client_msg_id: string; kind: MessageKind;
    body_text: string | null; audio_key: string | null; audio_duration_s: number | null;
    transcript: string | null; transcript_lang: string | null; created_at: Stamp;
    reply_to_task_id: Generated<string | null>;
  };
  attachments: { id: Id; message_id: string; r2_key: string; mime: string; size_bytes: number; width: number | null; height: number | null };
  tasks: {
    id: Id; message_id: string; thread_id: string; source: Generated<'app' | 'email' | 'whatsapp'>;
    subject: string | null; module: string | null; customer_name: string | null; customer_phone: string | null;
    customer_location: string | null; license_no: string | null; priority: Priority; details: string | null;
    status: Generated<TaskStatus>; assignee_id: string | null; tagged_user_id: string | null; department_id: string | null; team_id: Generated<string | null>;
    ai_status: Generated<AiStatus>; ai_error: string | null; ai_provider: string | null; prompt_version: string | null;
    overrides: Json<Overrides>; due_at: Date; closed_at: Date | null; created_at: Stamp; updated_at: Stamp;
    clock_state: Generated<ClockState>; clock_used_ms: Generated<number | string>; clock_running_since: Generated<Date | null>;
    used_before_transfer: Generated<number | string | null>; queued_at: Generated<Date | null>; accepted_at: Generated<Date | null>;
    completed_at: Generated<Date | null>; verified_at: Generated<Date | null>; resolution: Generated<string | null>;
    customer_informed: Generated<'yes' | 'no' | 'n/a' | null>; escalation_level: Generated<EscalationLevel | null>;
    escalated_to: Generated<string>; auto_escalated_at: Generated<Date | null>; head_alerted: Generated<boolean>;
    reassign_requested_by: Generated<string | null>; reassign_asked: Generated<string>; declined_by: Generated<string>;
    request: Generated<string | null>; warned: Generated<string>; transferred_from_id: Generated<string | null>;
    ticket_no: Generated<string | null>; parent_task_id: Generated<string | null>;
  };
  notifications: { id: Id; user_id: string; task_id: string; text: string; read_at: Date | null; created_at: Stamp };
  task_events: { id: Id; task_id: string; actor_id: string | null; type: TaskEventType; payload: Json<Record<string, unknown>>; created_at: Stamp };
}

export type User = Selectable<Database['users']>;
export type NewUser = Insertable<Database['users']>;
export type UserUpdate = Updateable<Database['users']>;
export type Department = Selectable<Database['departments']>;
export type Thread = Selectable<Database['threads']>;
export type Message = Selectable<Database['messages']>;
export type Task = Selectable<Database['tasks']>;
export type Team = Selectable<Database['teams']>;
