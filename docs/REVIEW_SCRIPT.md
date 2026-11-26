# Leadership review script (Phase 1)

About 20 minutes, two phones (or a phone and an emulator). Use **made-up customer details only**: the prototype's AI runs on free tiers.

**Before you start**

1. Install the Android build on both phones (Firebase App Distribution link, or `flutter build apk`).
2. On phone A, sign in as **Riya Shah (Support)**: `9800000002`. On phone B, sign in as **Tushar Parmar (Development head)**: `9800000004`.
3. The prototype code is `123456`.

Have someone on the backend keep this open: `http://<server>:8080/readyz` should show `"ok": true`.

| # | Do | Expect |
| --- | --- | --- |
| 1 | **Text task.** Phone A: tap the search bar, type "Devel", tap **Development**. Type: *Urgent – Profit NX login failing for all users at Mehta Traders, Surat. Call 98250 12345.* Send. | The chat opens straight away (no + step, no form). The bubble appears on the right at once with a clock, then the time and "Open". |
| 2 | Phone B: open the chat from Riya. | A task card on the left: **High**, module **Profit NX**, subject like "Profit NX Login Failure", customer Mehta Traders, phone 9825012345 (tap to call), location Surat. While AI works the card shows "Structuring…". |
| 3 | **Voice task.** Phone A, chat with **Dhaval Dalsania**: hold the mic, say in Hindi or Gujarati what is wrong and who the customer is, release. | A voice bubble on A. On B's side (sign in as Dhaval, `9800000005`): "Transcribing…" then a structured card with ▶ and "Show transcript". Readable without playing it. |
| 4 | **Slash override.** Phone A to Development: type *SQL install needed at Kaveri Steel*, then type `/pri`, pick **/priority → Low**, then `/customer` → *Kaveri Steel Ltd*. Send. | Chips appear above the box and the `/…` text disappears. The card on B shows **Low** and customer *Kaveri Steel Ltd*, whatever the AI thought. |
| 5 | **@mention.** Phone A to Development: *Check ERP sync @Vish*, pick **Vishwas**, send. | Card shows "Tagged: @Vishwas". Only Vishwas and the head get a push; the others see it in the chat without a push. |
| 6 | **Department accept.** Two Development phones (e.g. Dhaval and Vishwas) tap **Accept Task** on the same card together. | One gets the task; the other sees "<name> already accepted this task." Riya's bubble changes to "Accepted". |
| 7 | **Reassign.** Phone B (Tushar, head): on an accepted card tap **Reassign**, pick another member. | The card shows the new person; they and Riya are notified. |
| 8 | **Overdue.** Home screen on B: the **Overdue** button. | Lists open tasks past their time (High 4 h, Medium 24 h, Low 72 h), red "Overdue" badge. To show it at once, ask the backend to set one task's `due_at` in the past. |
| 9 | **Close.** As the assignee: **Mark In Progress**, then **Close**. | Card shows Closed; it leaves **My Pending** and appears under **Closed** for both sides. |
| 10 | **Offline.** Phone A: airplane mode, send a message, turn airplane mode off. | The message waits with a clock, then sends once; no duplicate task. |
| 11 | **Filters.** Home: **My Pending**, **Overdue**, **Closed**. | Three buttons in two rows, no sideways scrolling; counts on My Pending and Overdue. |

**Questions for the review** (from `docs/DECISIONS.md`): D1 filter set, D2 one department chat per requester, D3 push for tagged tasks, D4 cancel after sending, D5 sender seeing the card, D6 voice-note retention, D7 real sign-in source.
