# Task Plus with the Ornate Samanvay look

Owner's instruction (27 Nov 2026): keep Ornate Samanvay's UI and its basic features, keep every Task Plus feature. Phase 1 only; nothing from Phase 2 (email, WhatsApp) until after the leadership review. When in doubt, ask the owner.

## Owner decisions (27 Nov 2026)

| Question | Decision |
| --- | --- |
| How to get the look | Restyle the Flutter Android app (and the browser demo built from it) to look like Ornate |
| Home | Ornate bottom bar: My Tasks / Queue / All Cases / You; search; department picker; Filters dialog; chip row |
| Chips | All, Active, To Verify, Sent by me, Overdue/Escalated, Verified / Closed (Ornate's six, "Raised by Me" renamed) |
| Creating a task | Task Plus chat box only (text, dictation, voice notes, files, `/` commands, AI). No form |
| New task button | **+** opens Ornate's picker (person, team, department); picking opens their chat with the chat box |
| Chat rows | Ornate: one chat per person; an accepted task sits under the person holding it; unaccepted department/team tasks sit under that department/team. Summary line ("3 open · 2 from you · 1 not accepted · 1 overdue") |
| Inside a person's chat | Task Plus timeline of task cards (sent right, received left), with the summary line and All / Not accepted / Accepted chips |
| Tapping a task | Opens Ornate's case page: status strip, tabs Activity (All / Messages / Updates / Files), Details, Sub-Tasks, Files, Audit trail, the action card, and the chat box for that task |
| Ornate features brought back | Private notes (chat with yourself), Style (Standard / Google colours), chat wallpaper, light / dark / system, sub-tasks to another department |
| Sub-task | In a task's chat, type `/subtask`, pick a department; that message becomes the sub-task. Parent waits ("Waiting for another department", clock paused) until its sub-tasks finish. Department Head: "Complete – cancel open sub-tasks" |
| Bell | Yes: in-app notification list with unread count, tap opens the task, Mark all read |
| Edit before accept | Sender edits their message text while the task is Open; AI re-reads it and rebuilds the card |
| Unread badges | No |

## Not brought (unchanged)

Ornate's create form; follow-up after the reopen window; close by exception; progress stage; switch user outside the demo. Phase 2 items.

## Build order

1. **Server**: tab lists (My Tasks / Queue / All Cases rules from Ornate's `routing.ts`), chips, filters, department; person timeline; case activity; private notes; sub-tasks (`WaitingDept` status, `/subtask`, complete-cancel); notifications list; edit message while Open (AI re-reads).
2. **App look**: Ornate colours (light/dark, Standard/Google), floating bottom bar, list rows, search, chips, Filters dialog, bell, You page with Style, Light or dark, Chat wallpaper.
3. **App screens**: person chat (timeline + chips + composer), case page (strip, tabs, action card), + picker, private notes, `/subtask`, edit.
4. **Demo**: demo backend follows, republish the link.

Each step ends with tests passing and a commit.
