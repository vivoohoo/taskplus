# Status: done and pending

As of 27 Nov 2026. Plan source: "Task Plus Redesign: Change Summary & Implementation Guide" (26 Nov 2026), summarised in `d:\ticketmgmt\README.md` → "Pending: redesign". Architecture: [ARCHITECTURE.md](ARCHITECTURE.md). Ornate feature parity: [PARITY.md](PARITY.md). Owner decisions: [DECISIONS.md](DECISIONS.md).

Phase 1 is built. Phases 2 and 3 have not started. Phase 2 waits on the leadership review of Phase 1 on mobile.

## Phase 1: task creation and receiving (built)

| # | Change | Status | Where / note |
| --- | --- | --- | --- |
| 1 | Mobile first | Done | Flutter Android app; browser demo for sharing |
| 2 | Direct chat flow, no **+** or form | Done | Search a person, team or department → their chat |
| 3 | One timeline per person / department | Done | Sent on the right, received on the left; one chat per sender per department |
| 4 | Single input box: text, dictation, voice notes, files | Done | Composer; outbox keeps messages sent offline |
| 5 | Slash commands `/priority` `/customer` `/license` `/module` | Done | `/customer` picks from the customer list |
| 6 | AI structuring to JSON | Done | Background job; Groq works, Gemini key invalid; slash values override the AI. Vercel demo: same prompt via `api/ai.js` (needs `GROQ_API_KEY` in Vercel) |
| 7 | Sender vs recipient view | Done | Recipient gets the structured card; sender also sees it (owner decision D5) |
| 8 | Compact filters (3) | Done | My Pending, Overdue, Sent by me |
| 9 | Leadership review on mobile | **Pending** | Needs an APK in leadership's hands, or the demo link: https://claude.ai/artifact/13ZYxwZ5UbfrhD6sGZhsdg |

On top of the Phase 1 list, Ornate Samanvay's features were brought across (PARITY.md steps 1–5): passwords, teams and reporting line, full workflow with the working-hours clock and timers, ticket numbers, task details and history, Team screen for leads, away, shifts, holidays, notification settings, suggestions, and the browser demo.

## Phase 1 decisions (all made)

| Question | Decision |
| --- | --- |
| LLM provider | Free tiers (Groq + Gemini) on the office server, made-up customer data only |
| App form | Android store app (APK); iOS skipped for now |
| Speech to text | Groq Whisper for voice notes; phone dictation for typing |
| 3 filters | My Pending, Overdue, Sent by me |

## Pending

**Waiting on the owner**
- [ ] Valid Gemini key (starts `AIza`; the ones sent start `AQ.`).
- [ ] Firebase project files: Android `google-services.json` + service-account key. Push is off until then.
- [ ] Replace the Groq and Gemini keys pasted in chat.
- [ ] Leadership review of Phase 1 (the gate to Phase 2).

**Phase 1 loose ends**
- [ ] Release APK for the review, signed; server reachable through the tunnel.
- [ ] Rerun the emulator integration tests after workflow steps 3–4.
- [ ] Ornate features not brought yet: private notes, editing an Open task's text, verify for an away requester, in-app light/dark switch, read markers.
- [ ] Named Cloudflare tunnel + domain before wider use (quick tunnel address changes on restart).

**Phase 2: email and WhatsApp (not started)**
- [ ] Email to task: Gmail API (preferred) or an auto-forward inbox.
- [ ] Auto-close an email task when the agent replies to the customer's thread.
- [ ] WhatsApp capture from support messages and groups.

**Phase 3: calls and dashboards (not started)**
- [ ] Call server: after a call, turn it into a task with the recording.
- [ ] Call analytics: transcripts, tone scores, agent scorecards, live red-flag alerts.
- [ ] Dashboards by role: individual, team lead, department head, executive (the Team screen covers leads and heads today).

**Production switch** (ARCHITECTURE.md, "How to switch to production"): BullMQ + Redis worker, several API copies, paid or own-hardware AI, backups, monitoring.

## Tests

| Suite | Result |
| --- | --- |
| Server (real SQL Server in Docker) | 83 pass |
| App widget and unit | 23 pass |
| Demo backend | 2 pass |
| Emulator integration | Passed before workflow steps 3–4; rerun pending |
