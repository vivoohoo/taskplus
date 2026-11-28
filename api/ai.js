// The browser demo's AI: turns a message into ticket fields, like the real server's background job.
// POST { text, departmentName, modules[], senderName, recipientLabel } -> { subject, module, customerName, customerPhone,
//   customerLocation, licenseNo, priority, details }   or 503 when no key is set (the demo then uses its keyword reader).
// Prompt and checks are copies of server/src/ai/prompts/structure.v2.ts and server/src/ai/validate.ts: keep them in step.
// Free tier (owner decision): made-up customer data only. The key lives in Vercel > Settings > Environment Variables.
const KEY = process.env.GROQ_API_KEY;
const MODEL = process.env.GROQ_LLM_MODEL || 'openai/gpt-oss-120b';
const PRIORITIES = ['Critical', 'High', 'Medium', 'Low'];

const prompt = (i) => `You convert an internal staff message into a support/work ticket for Task Plus.
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

const schema = (modules) => ({
  type: 'object', additionalProperties: false,
  required: ['subject', 'module', 'customer_name', 'customer_phone', 'customer_location', 'license_no', 'priority', 'details'],
  properties: {
    subject: { type: 'string', maxLength: 60 }, module: { enum: modules },
    customer_name: { type: ['string', 'null'] }, customer_phone: { type: ['string', 'null'] }, customer_location: { type: ['string', 'null'] },
    license_no: { type: ['string', 'null'] }, priority: { enum: PRIORITIES }, details: { type: 'string' },
  },
});

const blank = (v) => (typeof v === 'string' && v.trim() ? v.trim() : null);
function phone(v) {
  let d = (blank(v) || '').replace(/\D/g, '');
  if (d.length === 12 && d.startsWith('91')) d = d.slice(2);
  return d.length === 10 || (d.length >= 11 && d.length <= 15) ? d : null;
}

/** Checks and cleans what the model returned (it never decides on its own what's allowed). Exported for the check below. */
function clean(r, modules) {
  if (!r || !blank(r.subject) || !blank(r.details)) return null;
  return {
    subject: r.subject.trim().slice(0, 60),
    module: modules.includes(r.module) ? r.module : 'Other',
    customerName: blank(r.customer_name), customerPhone: phone(r.customer_phone), customerLocation: blank(r.customer_location),
    licenseNo: blank(r.license_no)?.toUpperCase() ?? null,
    priority: PRIORITIES.includes(r.priority) ? r.priority : 'Medium',
    details: r.details.trim(),
  };
}

module.exports = async (req, res) => {
  res.setHeader('cache-control', 'no-store');
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only.' });
  if (!KEY) return res.status(503).json({ error: 'No AI key. Add GROQ_API_KEY in Vercel > Settings > Environment Variables.' });
  const b = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : req.body || {};
  // Anyone with the link can call this: keep requests small so the free quota lasts.
  if (typeof b.text !== 'string' || !b.text.trim() || b.text.length > 2000 || !Array.isArray(b.modules) || b.modules.length > 50) {
    return res.status(400).json({ error: 'Send { text (up to 2000 characters), modules, departmentName, senderName, recipientLabel }.' });
  }
  const modules = [...new Set([...b.modules.map(String), 'Other'])];
  const input = { text: b.text, modules, departmentName: String(b.departmentName || 'Unknown'), senderName: String(b.senderName || 'a colleague'),
    recipientLabel: String(b.recipientLabel || 'a colleague') };
  try {
    const r = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST', signal: AbortSignal.timeout(12_000),
      headers: { authorization: `Bearer ${KEY}`, 'content-type': 'application/json' },
      body: JSON.stringify({ model: MODEL, temperature: 0, response_format: { type: 'json_object' }, messages: [
        { role: 'system', content: `Reply with one JSON object matching this JSON schema:\n${JSON.stringify(schema(modules))}` },
        { role: 'user', content: prompt(input) },
      ] }),
    });
    if (!r.ok) return res.status(502).json({ error: `AI provider said ${r.status}.` });
    const text = (await r.json()).choices?.[0]?.message?.content ?? '';
    const out = clean(JSON.parse(text.replace(/^```(?:json)?\s*|\s*```$/g, '')), modules);
    return out ? res.status(200).json(out) : res.status(502).json({ error: 'AI reply failed checks.' });
  } catch (e) {
    return res.status(502).json({ error: `AI failed: ${e.message}` });
  }
};
module.exports.clean = clean;
