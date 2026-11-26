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

## Contradictions found in the spec (for Review 1)

- §3/§6 say PostgreSQL + Drizzle; owner chose SQL Server (decisions 1–2).
- §5 lists provider keys as required, §16 rule 5 says stub what's missing and continue: resolved by decision 8.
- §3 says Node 20 LTS; this PC has Node 24. Code targets Node ≥ 20; CI will run 20.
- §6 users have `phone (unique)` and §7 has OTP sign-in, but §18 D7 says the real auth source is still unknown.

## Proposed (not built)

- Per-device sign-out (stored refresh tokens) if staff share phones.
