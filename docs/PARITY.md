# Ornate Samanvay → Task Plus: what comes across

Owner's instruction (26 Nov 2026): Task Plus gets every point and feature of Ornate Samanvay (`d:\ticketmgmt`), except where they conflict with the Task Plus redesign. Owner's choices: **core workflow**, **teams + reporting line**, **zero-form creation only**, **clickable web demo** as the shared link.

Status: ✅ built · 🔨 to build · ⛔ not brought (conflicts) · ⏸ later phase

## Organisation

| Ornate feature | Task Plus | Notes |
| --- | --- | --- |
| Divisions (Development, Support, Marketing & Sales, HR) | 🔨 | Task Plus "departments" = divisions; add HR and Marketing & Sales to the seed |
| Teams inside a division, each with a Team Lead (ProfitNX → Dhaval, Ornate → Tushar, PowerBI → Vishwas) | 🔨 | New `teams` table; a user belongs to a team |
| Reporting line between leads (Vishwas → Dhaval → Tushar) | 🔨 | `users.reports_to_id`; reassign, escalate and analytics follow it |
| Department Head powers (Tushar leads Development) | ✅ / 🔨 | `dept_head` role exists; extend to "leads division" |
| Short role labels ("ProfitNX lead"), "Reporting manager: X" on the profile | 🔨 | Profile screen |

## Creating and routing

| Ornate feature | Task Plus | Notes |
| --- | --- | --- |
| Form: issue, priority, customer, details, attachments | ⛔ | Conflicts with zero-form. Replaced by chat box + AI + `/priority` `/customer` `/license` `/module` |
| Send to a person, a team, or a division's leads | ✅ / 🔨 | Person and department exist; add team as a target |
| @mentions (alerted, can accept) | ✅ | Tagged person |
| Named person is away → goes to their team; cover teams | 🔨 | Away setting + cover |
| Private notes (Self) | 🔨 | A chat with yourself; tasks never routed |
| Edit until accepted | 🔨 | Sender edits text/priority while Open |
| Cancel | ✅ decided, 🔨 | Sender, while Open (D4) |
| Lead assigns to a team member | 🔨 | `assign` on an Open task |
| Workload limit (5 active), "full" badge | 🔨 | Shown in assign/reassign pickers |
| Customer list (Mehta Traders, …) | 🔨 | Becomes the `/customer` picker + AI matches names to it |

## Workflow (core, chosen)

| Ornate feature | Task Plus | Notes |
| --- | --- | --- |
| Pending Acceptance → In Progress | ✅ | Open → Accepted/InProgress |
| Decline (named person) | 🔨 | |
| Ask Team Lead to reassign (once a day); lead sees only Reassign / Keep it with me | 🔨 | |
| Reassign | ✅ | Extend to team leads up the reporting line |
| **Completed → Verify → Close** (resolution + "customer informed?"), auto-verify after 2 working days, auto-close after 3 | 🔨 | New statuses Completed, Verified |
| **Ask requester** → Waiting for Information (clock pauses until they reply) | 🔨 | |
| **Blocked / Unblock** (clock stops) | 🔨 | |
| **Reject / Transfer**: staff ask, lead approves or refuses; leads act directly | 🔨 | New statuses Rejected, Transferred |
| **Reopen** within 7 days | 🔨 | |
| **Escalate** to Team Leader / Department Head / Management; next level if nobody holds it; Attend escalation | 🔨 | |
| Change priority (staff raise only, leads lower) | 🔨 | |
| Verify on behalf of an away requester | 🔨 | |
| Hand off sub-task to another division (Waiting for Another Dept) | ⛔ (core chosen) | Skipped |
| Follow-up after the reopen window | ⛔ (core chosen) | Skipped |
| Close by exception, Complete & cancel sub-tasks, Progress stage | ⛔ (core chosen) | Skipped |

## Time

| Ornate feature | Task Plus | Notes |
| --- | --- | --- |
| Working-hours clock: shifts 9–6 / 10–7 / 11–8, Mon–Sat, Sundays and public holidays skipped | 🔨 | Replaces flat SLA hours; `due_at` from working time |
| Accept limits (Critical 15 min … Low 4 h) and complete limits (4 h … 7 days) | 🔨 | Task Plus has High/Medium/Low: add **Critical** |
| Warnings at 75% and 1 h left; overdue alerts to leads | 🔨 | Timer job |
| Not accepted in time → auto-escalate → Division Lead alert after 1 h | 🔨 | |
| Clock pauses (waiting/blocked), restarts on transfer, time used before transfer kept | 🔨 | Uses `clock_segments`-style tracking |
| Public holidays screen (leads) | 🔨 | |
| Shift per person (You > Shift; leads set their team's) | 🔨 | |

## People and settings

| Ornate feature | Task Plus | Notes |
| --- | --- | --- |
| Away (lead alerted, routed to team, no new work) | 🔨 | |
| Notification settings (optional kinds can be muted; must-haves always on) | 🔨 | |
| Suggest an improvement (head marks New/Seen/Planned/Done/Not planned) | 🔨 | |
| Light / dark / system | 🔨 | |
| Style (Standard / Google colours), chat wallpaper | ⏸ | Cosmetic; after the trial |
| Switch user (demo) | ✅ in web demo only | Never in the real app |

## Views

| Ornate feature | Task Plus | Notes |
| --- | --- | --- |
| Tabs My Tasks / Queue / All Cases, 6 chips, department picker, Filters dialog | ⛔ | Conflicts with the 3-button filter block (My Pending, Overdue, Sent by me) and the chat list |
| One chat per person, open tickets only, summary line, Not accepted / Accepted filter | 🔨 | Chat list groups by person; header shows "3 open · 2 from you · 1 not accepted · 1 overdue" |
| Ticket page tabs: Activity, Details, Audit trail, Files (Sub-tasks skipped) | 🔨 | Task card opens a details sheet with these |
| Activity cards for every event | 🔨 | Event cards in the timeline |
| Search across tickets (id, subject, people) | 🔨 | Search screen gets a "Tasks" section |
| Ticket numbers ORN-SS-2627-00042 | 🔨 | Shown on cards; financial-year prefix |
| Team performance (needs attention, this month, on time by priority, moved & escalated, people, teams, sources, customers, repeat problems, oldest) | 🔨 | Leads' "Team" screen |

## Data and server

| Ornate feature | Task Plus | Notes |
| --- | --- | --- |
| Own passwords, lock after 5 tries, admin reset | 🔨 | D7 |
| Insert-only history, time held per person, read markers | 🔨 | `task_events` (exists) + clock segments |
| Files on the office server disk, 180-day retention | 🔨 | Decided |
| SQL Server | ✅ | |

## Build order

1. **Review-6 decisions** — passwords, disk storage + retention, cancel, filters (Sent by me), tagged push, sender sees card, server-address setting.
2. **Organisation** — teams, team leads, reporting line, HR + Marketing & Sales, profile.
3. **Workflow** — new statuses and actions above, with the working-hours clock and timers.
4. **People, views, analytics** — away/cover, notification settings, suggestions, holidays, shifts, details sheet (audit, files), task search, ticket numbers, Team screen, customers.
5. **Web demo** — Flutter web build with an in-browser demo backend and sample data, published as the shared link.

Each step ends with tests passing and a commit.
