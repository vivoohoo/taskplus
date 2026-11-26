// npm run seed: 3 departments with module lists and a head each, 10 people in total. Safe to run again.
// Phone numbers are made up (98000 000xx). Sign in with any of them and DEV_FIXED_OTP.
import { fileURLToPath } from 'node:url';
import { loadEnv } from '../config/env';
import { createDb, type Db } from './client';
import type { Role } from './schema';

export const SEED = {
  departments: [
    { name: 'Support', modules: ['Profit NX', 'SQL Installation', 'Licensing', 'Printing', 'Other'] },
    { name: 'Development', modules: ['Profit NX', 'Ornate', 'Power BI', 'Mobile App', 'Other'] },
    { name: 'Sales', modules: ['Demo Request', 'Quotation', 'Renewal', 'New License', 'Other'] },
  ],
  users: [
    { name: 'Support Lead', phone: '9800000001', dept: 'Support', role: 'dept_head' },
    { name: 'Riya Shah', phone: '9800000002', dept: 'Support', role: 'staff' },
    { name: 'Karan Patel', phone: '9800000003', dept: 'Support', role: 'staff' },
    { name: 'Tushar Parmar', phone: '9800000004', dept: 'Development', role: 'dept_head' },
    { name: 'Dhaval Dalsania', phone: '9800000005', dept: 'Development', role: 'staff' },
    { name: 'Vishwas', phone: '9800000006', dept: 'Development', role: 'staff' },
    { name: 'Nisha Patel', phone: '9800000007', dept: 'Development', role: 'staff' },
    { name: 'Sales Lead', phone: '9800000008', dept: 'Sales', role: 'dept_head' },
    { name: 'Priya Nair', phone: '9800000009', dept: 'Sales', role: 'staff' },
    { name: 'Admin', phone: '9800000010', dept: null, role: 'admin' },
  ] as { name: string; phone: string; dept: string | null; role: Role }[],
};

export async function seed(db: Db) {
  const deptIds = new Map<string, string>();
  for (const d of SEED.departments) {
    const found = await db.selectFrom('departments').select('id').where('name', '=', d.name).executeTakeFirst();
    const id = found?.id ?? (await db.insertInto('departments').values({ name: d.name, modules: JSON.stringify(d.modules) })
      .output('inserted.id').executeTakeFirstOrThrow()).id;
    deptIds.set(d.name, id);
  }
  for (const u of SEED.users) {
    const found = await db.selectFrom('users').select('id').where('phone', '=', u.phone).executeTakeFirst();
    const id = found?.id ?? (await db.insertInto('users').values({
      name: u.name, phone: u.phone, role: u.role, department_id: u.dept ? deptIds.get(u.dept)! : null,
    }).output('inserted.id').executeTakeFirstOrThrow()).id;
    if (u.role === 'dept_head' && u.dept) await db.updateTable('departments').set({ head_user_id: id }).where('id', '=', deptIds.get(u.dept)!).execute();
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const db = createDb(loadEnv().DATABASE_URL);
  try { await seed(db); console.log(`Seeded ${SEED.departments.length} departments and ${SEED.users.length} people.`); } finally { await db.destroy(); }
}
