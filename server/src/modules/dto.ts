// What the API sends: camelCase, ISO dates, JSON columns parsed. One place so every endpoint matches.
import type { Message, Task } from '../db/schema';

const iso = (d: Date | null) => (d ? new Date(d).toISOString() : null);

export interface AttachmentRow { id: string; message_id: string; r2_key: string; mime: string; size_bytes: number; width: number | null; height: number | null }

export const messageDto = (m: Message, attachments: AttachmentRow[] = []) => ({
  id: m.id,
  threadId: m.thread_id,
  senderId: m.sender_id,
  clientMsgId: m.client_msg_id.toLowerCase(),
  kind: m.kind,
  bodyText: m.body_text,
  audioKey: m.audio_key,
  audioDurationS: m.audio_duration_s,
  transcript: m.transcript,
  transcriptLang: m.transcript_lang,
  attachments: attachments.map((a) => ({ id: a.id, key: a.r2_key, mime: a.mime, sizeBytes: a.size_bytes, width: a.width, height: a.height })),
  replyToTaskId: m.reply_to_task_id,
  createdAt: iso(m.created_at),
});

const parseJson = <T>(s: unknown, d: T): T => { try { return typeof s === 'string' ? (JSON.parse(s) as T) : d; } catch { return d; } };

export const taskDto = (t: Task, warnings: string[] = [], actions: string[] = []) => ({
  id: t.id,
  ticketNo: t.ticket_no,
  messageId: t.message_id,
  threadId: t.thread_id,
  source: t.source,
  subject: t.subject,
  module: t.module,
  customerName: t.customer_name,
  customerPhone: t.customer_phone,
  customerLocation: t.customer_location,
  licenseNo: t.license_no,
  priority: t.priority,
  details: t.details,
  status: t.status,
  assigneeId: t.assignee_id,
  taggedUserId: t.tagged_user_id,
  departmentId: t.department_id,
  aiStatus: t.ai_status,
  aiError: t.ai_error,
  overrides: JSON.parse(t.overrides as unknown as string) as Record<string, string>,
  warnings,
  dueAt: new Date(t.due_at).getUTCFullYear() >= 9999 ? null : iso(t.due_at), // paused clock: no due time
  teamId: t.team_id,
  clock: { state: t.clock_state, usedMs: Number(t.clock_used_ms), runningSince: iso(t.clock_running_since), usedBeforeTransfer: t.used_before_transfer == null ? null : Number(t.used_before_transfer) },
  acceptedAt: iso(t.accepted_at),
  completedAt: iso(t.completed_at),
  verifiedAt: iso(t.verified_at),
  resolution: t.resolution,
  customerInformed: t.customer_informed,
  escalationLevel: t.escalation_level,
  escalatedTo: parseJson<string[]>(t.escalated_to, []),
  reassignRequestedBy: t.reassign_requested_by,
  request: parseJson<Record<string, unknown> | null>(t.request, null),
  transferredFromId: t.transferred_from_id,
  /** The buttons this viewer gets (the server's rules). */
  actions,
  closedAt: iso(t.closed_at),
  createdAt: iso(t.created_at),
  updatedAt: iso(t.updated_at),
});

export type MessageDto = ReturnType<typeof messageDto>;
export type TaskDto = ReturnType<typeof taskDto>;
