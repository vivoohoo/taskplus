// Spec §9.4: code never extracts, it only checks and cleans what the LLM returned, then applies the sender's overrides.
import type { Overrides, Priority } from '../db/schema';
import { taskExtraction } from './schema/taskExtraction';

export interface Structured {
  subject: string; module: string; customer_name: string | null; customer_phone: string | null;
  customer_location: string | null; license_no: string | null; priority: Priority; details: string;
}
export type ValidateResult = { ok: true; value: Structured; warnings: string[] } | { ok: false; error: string };

const blank = (v: string | null) => (v === null || !v.trim() ? null : v.trim());

/** Phone: digits only; a 12-digit number starting 91 loses the 91; 10 digits, or 11–15 for international. */
export function cleanPhone(v: string | null): { value: string | null; warning?: string } {
  if (!blank(v)) return { value: null };
  let d = v!.replace(/\D/g, '');
  if (d.length === 12 && d.startsWith('91')) d = d.slice(2);
  if (d.length === 10 || (d.length >= 11 && d.length <= 15)) return { value: d };
  return { value: null, warning: 'customer_phone: not a valid number, removed' };
}

export function cleanLicense(v: string | null, pattern?: string): { value: string | null; warning?: string } {
  const s = blank(v)?.toUpperCase() ?? null;
  if (!s) return { value: null };
  if (pattern && !new RegExp(pattern).test(s)) return { value: null, warning: 'license_no: does not match the licence format, removed' };
  return { value: s };
}

export function validateExtraction(raw: unknown, ctx: { modules: string[]; overrides: Overrides; licenseRegex?: string }): ValidateResult {
  // 1. Shape. A module outside the list is not a hard failure: it becomes "Other" (step 4).
  const schema = taskExtraction(ctx.modules).extend({ module: taskExtraction(ctx.modules).shape.subject });
  const parsed = schema.safeParse(raw);
  if (!parsed.success) return { ok: false, error: `AI output failed checks: ${parsed.error.issues.slice(0, 3).map((i) => `${i.path.join('.')} ${i.message}`).join('; ')}` };
  const r = parsed.data;
  const warnings: string[] = [];

  // 2–3. Phone and licence.
  const phone = cleanPhone(r.customer_phone);
  if (phone.warning) warnings.push(phone.warning);
  const license = cleanLicense(r.license_no, ctx.licenseRegex);
  if (license.warning) warnings.push(license.warning);

  // 4. Module must be one of the department's.
  const module = ctx.modules.includes(r.module) ? r.module : 'Other';

  const value: Structured = {
    subject: r.subject.trim().slice(0, 60),
    module,
    customer_name: blank(r.customer_name),
    customer_phone: phone.value,
    customer_location: blank(r.customer_location),
    license_no: license.value,
    priority: r.priority,
    details: r.details.trim(),
  };

  // 5. The sender's slash-command values always win.
  const o = ctx.overrides;
  if (o.priority) value.priority = o.priority;
  if (o.module) value.module = ctx.modules.includes(o.module) ? o.module : 'Other';
  if (o.license) value.license_no = o.license.trim().toUpperCase();
  if (o.customer) {
    if (/^[\d\s+()-]+$/.test(o.customer)) value.customer_phone = cleanPhone(o.customer).value ?? o.customer.replace(/\D/g, '');
    else value.customer_name = o.customer.trim();
  }
  return { ok: true, value, warnings };
}
