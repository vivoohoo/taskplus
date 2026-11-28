# Decisions

One line each: decision — reason — alternative.

## Made

| # | Decision | Reason | Alternative |
| --- | --- | --- | --- |
| 1 | **SQL Server instead of PostgreSQL** | Owner's decision (24 and 26 Nov 2026): the office server runs SQL Server | PostgreSQL as written in the spec |
| 2 | **Kysely + tedious instead of Drizzle** | Drizzle has no SQL Server support; Kysely is a typed query builder in the same style, with an MSSQL dialect and a migrator | Prisma (heavier, generated client) |
| 3 | Migrations are TypeScript files with raw SQL, listed in `db/migrate.ts`; `npm run migrate` only, never schema push | Spec §12: migrations only in production | Prisma migrate |
| 4 | JSON columns (`departments.modules`, `tasks.overrides`, `task_events.payload`) are `nvarchar(max)` with `ISJSON` checks | SQL Server has no `jsonb` or `text[]` | Child tables for modules |
| 5 | `uniqueidentifier` keys with `NEWSEQUENTIALID()` | UUID keys as specified, without index fragmentation | `NEWID()` |
| 6 | Direct threads: the app stores the pair in a fixed order and a filtered unique index stops duplicates; the database only checks the two users differ | SQL Server orders GUIDs differently from strings, so a `user_a < user_b` check would disagree with the app | Sort by SQL Server GUID order in the app |
| 7 | Refresh tokens are signed JWTs (`typ: refresh`, 30 days), not stored | Keeps the API stateless (spec §12); revoke all by rotating `JWT_SECRET` | Store hashed refresh tokens to allow per-device sign-out |
| 8 | Provider keys (Gemini, Groq, R2, Firebase) are checked when the provider is first used; `DATABASE_URL` and `JWT_SECRET` at startup | Lets M1–M2 run before keys exist (rule 5: stub, don't block) | Require all keys at startup |
| 9 | OTP verify answers "Wrong number or code" for unknown numbers too, and OTP request always says sent | Numbers can't be probed | Tell the user the number is unknown |
| 10 | Pinned: Node ≥ 20 (dev machine runs 24), Fastify 5.12, Zod 4.6, Kysely 0.28, tedious 19, pino 10, @fastify/jwt 10, @fastify/rate-limit 11, Vitest 3.2, TypeScript 5.9, Testcontainers 12 | Majors I know well; newest majors (TypeScript 7, Vitest 5) skipped for now | Latest of everything |
| 11 | AI prototype runs on free tiers with **made-up customer data only** | Owner's decision: free tiers may use content for training | Paid tier from day one |
| 12 | Built in a new repo `d:\ticketmgmt\taskplus`; the earlier Ornate Samanvay web app and SQL Server API stay untouched | Owner's decision | Replace the earlier server |
| 13 | Rate limits run after the body is parsed (`hook: preHandler`) so OTP limits can key on the phone number | Spec §13: 10 OTP requests/hour per phone | Limit by IP |
| 14 | `GET /files/url?key=` instead of `GET /files/:key/url` | Keys contain slashes (`dept/yyyy/mm/uuid.ext`) | Encode the key in the path |
| 15 | `POST /uploads/presign` also takes `threadId` | The key's folder is the thread's department (or `direct`), and access is checked before signing | Folder chosen when the message is sent (would need a copy in R2) |
| 16 | Without R2 keys (dev only) files go to an in-memory store served at `/v1/dev-upload/*` | Lets voice and attachments work before R2 is set up; refused in production | Require R2 from day one |
| 17 | A message's attachment size and type come from a storage `HEAD` | Proves the upload exists and is in this thread's folder before the task is saved | Trust the phone's values |
| 18 | Added `GET /departments/:id` (members, modules, head) and `GET /tasks/counts` | The app needs members for @mention and Reassign, modules for `/module`, counts for the filter badges | Put them in other responses |
| 19 | `/tasks` cursor is a numeric offset | Results are sorted by due date/closed date, which change; simple and correct for Phase 1 volumes | Keyset cursor |
| 20 | A direct-chat task uses the recipient's department for its module list and for Reassign | Direct tasks have no department of their own | Sender's department |
| 21 | Message rate limit reads the user from the token itself | The limiter can run before sign-in is checked; keying on an empty id would share one limit between everyone | Limit by IP |
| 22 | Message page cursor compares times inside SQL | The driver rounds JS dates to ~3 ms, which skipped or repeated messages at page edges (caught by a test) | Send times as datetime2 parameters |
| 23 | Worker emits Socket.IO events through `@socket.io/redis-emitter` | Workers have no HTTP server; phones still get `task.structured` live | Workers call back into the API |
| 24 | App: Flutter 3.50.1 (Material via `material_ui`), Riverpod 3.5, go_router 18.1, dio 5.11, drift 2.35, socket_io_client 3.1, record 7.2, just_audio 0.10, speech_to_text 7.5, firebase_messaging 17.1, flutter_local_notifications 23.0 | Current stable lines when built | — |
| 25 | Push is off (quietly) until Firebase config files are added | The app must build and run before a Firebase project exists | Fail at start-up |
| 26 | Open decisions D1–D6 are built as proposed (My Pending/Overdue/Closed; one department chat per requester; tagged push to tagged person + head; sender sees only their bubble; voice-note lifecycle via R2 rule). D4 (cancel while Open) is **not** built yet | Proposals in the spec; D4 needs your yes | — |

## Owner decisions, 26 Nov 2026 (Review 6)

| # | Question | Decision | Changes needed |
| --- | --- | --- | --- |
| D1 | Filter set | **My Pending, Overdue, Sent by me** (Closed dropped) | Replace `closed` filter with `sent_by_me` (open tasks I sent) in API + app |
| D2 | Department chats | **One chat per sender** | None (as built) |
| D3 | Push for a tagged department task | **Tagged person only** | Drop the head from tagged-task push recipients |
| D4 | Sender cancel | **Yes, while still Open** | New `POST /tasks/:id/cancel`, status `Cancelled`, card + push |
| D5 | Sender sees the AI card | **Always shown** | Show the task card under each sent message (sender's actions: Cancel) |
| D6 | File retention | **180 days**, then delete the file; task, text and transcript stay | Nightly clean-up job |
| D7 | Sign-in | **Own passwords** (user ID or phone + password, 5 wrong tries lock 15 min, admin resets) | Replace OTP stub with password sign-in, as in the earlier office-server design |
| — | File storage | **Office server disk**, not R2 | Disk storage adapter with signed upload/download links served by our API |
| — | AI provider | **Free tiers (Gemini + Groq), made-up customer data only** | Owner creates two free API keys |
| — | Push | **Owner creates the Firebase project** and sends `google-services.json`, `GoogleService-Info.plist` and the service-account key | Wire in once received |
| — | Trial phones | **Android only** for now (iOS skipped, 26 Nov) | No Apple account or Mac needed yet |
| — | Server access | **Cloudflare quick tunnel** (`cloudflared tunnel --url http://localhost:8080`): free HTTPS, no account or domain; the trycloudflare.com address changes on every restart | App gets a "Server address" setting on the sign-in screen so a new address needs no new APK; move to a named tunnel + domain before wider rollout |

## Owner decisions, 27 Nov 2026 (Ornate look)

Keep Ornate Samanvay's UI and basic features with every Task Plus feature; Phase 1 only, nothing from Phase 2 until the leadership review; when in doubt, ask. Full list in [ORNATE_UI.md](ORNATE_UI.md). Note: the home screen follows Ornate's tabs and six chips, which goes beyond Phase 1 item 8 ("at most 3 buttons"); the owner chose this.

## Owner decisions, 27 Nov 2026 (sender view, clock, demo data)

| Question | Decision |
| --- | --- |
| What the sender sees | One line under their message: ticket number, subject, who has it, status. No cards, no buttons, in the app and the demo. Replaces D5 (sender sees the AI card), D4 (sender cancels) and the sender's verify / close / reopen / edit / escalate |
| Who closes a task | Nobody needs to: Completed verifies itself after 2 working days and closes 3 working days later (timers) |
| Clock pauses | None. Blocked and Waiting for another department keep the clock running; "Ask requester" removed (owners ask in the chat) |
| Person-to-person tasks (28 Nov) | Private to the sender, the receiver and whoever it's reassigned to. A lead or head sees it only when it's escalated to them (then fully, with actions) or a staff request (reassign, reject, transfer) waits on them. The Team screen counts these tasks in its numbers but never lists them; no overdue alerts about them go to leads. Not accepted in time: escalates to the receiver's team lead |
| Sender reopens (28 Nov) | The sender's only button: Reopen, on Completed / Verified / Closed within 7 days |
| Demo data on Vercel | Shared Postgres (Supabase or Neon from Vercel Storage) through `api/state.js`; every browser and account sees the same tasks |

## Contradictions found in the spec (for Review 1)

- §3/§6 say PostgreSQL + Drizzle; owner chose SQL Server (decisions 1–2).
- §5 lists provider keys as required, §16 rule 5 says stub what's missing and continue: resolved by decision 8.
- §3 says Node 20 LTS; this PC has Node 24. Code targets Node ≥ 20; CI will run 20.
- §6 users have `phone (unique)` and §7 has OTP sign-in, but §18 D7 says the real auth source is still unknown.

## Proposed (not built)

- Per-device sign-out (stored refresh tokens) if staff share phones.
- Read/unread per chat (Phase 1 shows open-task counts only).
- An admin screen for people and departments (today: seed script / SQL).
