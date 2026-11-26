// Prompt v1 (spec §9.3). Changing the wording means a new file and a new PROMPT_VERSION, so results can be compared.
export const PROMPT_VERSION = 'structure.v1';

export interface PromptInput { departmentName: string; modules: string[]; senderName: string; recipientLabel: string; text: string }

export function structurePrompt(i: PromptInput) {
  return `You convert an internal staff message into a support/work ticket for Task Plus.
The message may be English, Hindi, Gujarati, or a mix, and may be a speech transcript with errors.

Department: ${i.departmentName}
Allowed modules: ${i.modules.join(', ')}  (choose the closest; use "Other" if none fit)
Sender: ${i.senderName}   Recipient: ${i.recipientLabel}

Rules:
- Extract only what is stated. Never invent names, numbers or licence IDs; use null if absent.
- Phone numbers: digits only, keep country code if spoken.
- Priority: High if the message signals urgency (urgent, critical, asap, down, not working for all users, जल्दी, તાત્કાલિક ...);
  Low if explicitly minor/whenever; otherwise Medium.
- subject: short, specific, ≤ 60 chars, e.g. "Profit NX Login Failure", "SQL Installation Request".
- details: rewrite clearly as 1–5 short sentences or bullets; keep every technical detail.
Return only JSON matching the schema.

Message:
"""${i.text.replace(/"""/g, '"​""')}"""`;
}
