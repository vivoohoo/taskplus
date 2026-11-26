// Customer data is personal data: logs show only enough to recognise a value, never the whole thing.

/** "9876543210" -> "********10" */
export function maskDigits(v: string): string {
  const d = v.replace(/\D/g, '');
  return d.length <= 2 ? '*'.repeat(d.length) : '*'.repeat(d.length - 2) + d.slice(-2);
}

/** "LIC-ABC-12345" -> "LI***45" */
export function maskId(v: string): string {
  const s = v.trim();
  return s.length <= 4 ? '*'.repeat(s.length) : `${s.slice(0, 2)}***${s.slice(-2)}`;
}

/** Message bodies are never logged; only their length. */
export const maskText = (v: string) => `[${v.length} chars]`;

/** Field names whose values are masked wherever they appear in a log object. */
export const SENSITIVE: Record<string, (v: string) => string> = {
  phone: maskDigits,
  customer_phone: maskDigits,
  customerPhone: maskDigits,
  license_no: maskId,
  licenseNo: maskId,
  license: maskId,
  body_text: maskText,
  bodyText: maskText,
  transcript: maskText,
  details: maskText,
  otp: () => '******',
};

/** Deep copy with sensitive fields masked. */
export function maskObject(value: unknown, depth = 0): unknown {
  if (depth > 6 || value === null || typeof value !== 'object') return value;
  if (Array.isArray(value)) return value.map((v) => maskObject(v, depth + 1));
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(value)) {
    const m = SENSITIVE[k];
    out[k] = m && typeof v === 'string' ? m(v) : maskObject(v, depth + 1);
  }
  return out;
}
