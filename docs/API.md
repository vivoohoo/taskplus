# API

Base path `/v1`. JSON in and out. Signed-in calls send `Authorization: Bearer <accessToken>`.

Errors always look like `{ "error": { "code": "…", "message": "…", "details": … } }`. The `message` is written for people and can be shown as it is.

| Status | code | When |
| --- | --- | --- |
| 400 | `BAD_REQUEST` | Body or query failed checks; `details` lists `{field, message}` |
| 401 | `UNAUTHORIZED` | Missing, expired or wrong token (the app refreshes once, then signs out) |
| 403 | `FORBIDDEN` | Not allowed to see or do this |
| 404 | `NOT_FOUND` | |
| 409 | `ALREADY_ACCEPTED`, `CHANGED` | Someone else got there first |
| 429 | `RATE_LIMITED` | 30 messages a minute per person; 10 OTP requests an hour per phone |
| 501 | `OTP_NOT_CONFIGURED` | Sign-in is not connected (no `DEV_FIXED_OTP`, real auth pending: D7) |

Ids are UUIDs. The server returns them in upper case and accepts either case.

## Sign-in

| Method & path | Body | Returns |
| --- | --- | --- |
| `POST /auth/otp/request` | `{ phone }` | `{ sent: true }`, also for unknown numbers |
| `POST /auth/otp/verify` | `{ phone, code }` | `{ accessToken, refreshToken, user }`. Access lasts 15 min, refresh 30 days. |
| `POST /auth/refresh` | `{ refreshToken }` | A new pair + `user` |
| `GET /me` | | `{ id, name, role, departmentId, avatarUrl }` |
| `POST /devices` | `{ fcmToken, platform: android\|ios }` | 204. Upsert; a token moves to whoever signed in last on that phone. |

Phones are accepted with or without `+91` / a leading `0`.

## People, departments, threads

| Method & path | Returns |
| --- | --- |
| `GET /search?q=` | `{ results: [{ type: user\|department, id, name, subtitle }] }`, max 20. Empty `q`: recent chats first. |
| `GET /departments/:id` | `{ id, name, headUserId, modules: [..], members: [{ id, name, role }] }` |
| `POST /threads/open` | Body `{ targetType: user\|department, targetId }` → `{ thread }`. Gets or creates; never duplicates. |
| `GET /threads` | `{ threads: [{ id, type, title, subtitle, departmentId, requesterId, lastMessage, lastMessageAt, openTasks }] }`, newest first |

A department thread is one per (requester, department). The requester sees it titled with the department; members see it titled with the requester and "To <department>".

## Messages

`GET /threads/:id/messages?before=<messageId>&limit=30`, newest page first, items oldest first within the page:

```json
{ "items": [{ "message": { … }, "task": { … } }], "nextCursor": "<oldest message id, or null>" }
```

`POST /threads/:id/messages`:

```json
{
  "clientMsgId": "uuid made on the phone",
  "kind": "text | voice | attachment",
  "bodyText": "≤ 4,000 characters",
  "audioKey": "key from /uploads/presign",
  "audioDurationS": 12,
  "attachmentKeys": ["…"],
  "overrides": { "priority": "High", "customer": "Mehta Traders or 98250 12345", "license": "…", "module": "…" },
  "taggedUserId": "uuid (department threads only)"
}
```

Returns `201 { message, task }` with `task.aiStatus = "pending"`. The same `clientMsgId` again returns `200` with the same objects.

**message:** `id, threadId, senderId, clientMsgId, kind, bodyText, audioKey, audioDurationS, transcript, transcriptLang, attachments[{ key, mime, sizeBytes }], createdAt`

**task:** `id, messageId, threadId, source, subject, module, customerName, customerPhone, customerLocation, licenseNo, priority, details, status (Open|Accepted|InProgress|Closed), assigneeId, taggedUserId, departmentId, aiStatus (pending|done|needs_review), aiError, overrides, warnings[], dueAt, closedAt, createdAt, updatedAt`

`warnings` are check hints such as `"customer_phone: not a valid number, removed"`; the app shows ⚠ next to that field.

## Files

| Method & path | Body / query | Returns |
| --- | --- | --- |
| `POST /uploads/presign` | `{ threadId, mime, sizeBytes, purpose: audio\|attachment }` | `{ url, key, expiresAt, headers }`. `PUT` the file to `url` with `headers`. |
| `GET /files/url?key=` | | `{ url, expiresAt }` once the caller is checked against the thread |

Allowed: `audio/ogg`, `audio/opus`, `audio/mp4` (m4a), `image/jpeg`, `image/png`, `application/pdf`; up to 10 MB. Links expire after `PRESIGN_TTL_SECONDS`. Keys look like `{departmentId|direct}/{yyyy}/{mm}/{uuid}.{ext}`.

## Tasks

| Method & path | Who | Notes |
| --- | --- | --- |
| `POST /tasks/:id/accept` | The recipient (direct) or a department member, not the sender | Atomic. 409 `ALREADY_ACCEPTED` with `details.acceptedBy` |
| `POST /tasks/:id/reassign` `{ assigneeId }` | Department head or current assignee | Target must be in the same department; status stays Accepted |
| `POST /tasks/:id/status` `{ status: InProgress\|Closed }` | Assignee | Accepted → InProgress → Closed, or Accepted → Closed |
| `GET /tasks?filter=my_pending\|overdue\|closed&cursor=0` | | `{ items: [{ message, task }], nextCursor }` |
| `GET /tasks/counts` | | `{ myPending, overdue }` for the filter badges |

## Real time (Socket.IO, same host)

Connect with `auth: { token: <accessToken> }`. You join `user:{id}` and `dept:{departmentId}` automatically. Emit `thread.join` / `thread.leave` with a thread id while a chat is open.

| Event | Payload |
| --- | --- |
| `message.created` | `{ message, task }` |
| `task.transcribed` | `{ taskId, messageId, transcript }` |
| `task.structured` | `{ task }` |
| `task.updated` | `{ task, event: { type, payload } }` |

Events can arrive late or twice: keep the task with the newest `updatedAt`.

## Health

`GET /healthz` (process up) · `GET /readyz` (database, plus Redis when used; 503 if not) · `GET /metrics` (Prometheus).
