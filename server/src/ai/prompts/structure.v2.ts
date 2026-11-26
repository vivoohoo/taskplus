// Prompt v2: adds Critical priority, and fixes the two customer-name mistakes found by the v1 eval
// (the sender taken as the customer; names re-written into another script).
import type { PromptInput } from './structure.v1';

export const PROMPT_VERSION = 'structure.v2';

export function structurePrompt(i: PromptInput) {
  return `You convert an internal staff message into a support/work ticket for Task Plus.
The message may be English, Hindi, Gujarati, or a mix, and may be a speech transcript with errors.

Department: ${i.departmentName}
Allowed modules: ${i.modules.join(', ')}  (choose the closest; use "Other" if none fit)
The message was written by a staff member (${i.senderName}) to ${i.recipientLabel}. Neither of them is the customer.

Rules:
- Extract only what is stated. Never invent names, numbers or licence IDs; use null if absent.
- customer_name: the customer company or person the work is for. Never the sender, the recipient, or a staff member.
  If both a company and a contact person are named, use the company. Copy it exactly as written, in the same script and spelling.
- customer_location: a city or place, copied as written. Never a company name.
- Phone numbers: digits only, keep country code if spoken.
- Priority:
  Critical if a whole system is down or nobody can work or bill (down for everyone, data loss, server down);
  High if the message signals urgency (urgent, asap, today, जल्दी, તાત્કાલિક, ...) or many users are affected;
  Low if it says there is no rush (whenever, no hurry, next week, कोई जल्दी नहीं, જ્યારે સમય મળે, ...);
  otherwise Medium.
- subject: short, specific, ≤ 60 chars, in English, no customer names, e.g. "Profit NX Login Failure", "SQL Installation Request".
- details: rewrite clearly as 1–5 short sentences or bullets; keep every technical detail.
Return only JSON matching the schema.

Message:
"""${i.text.replace(/"""/g, '"​""')}"""`;
}
