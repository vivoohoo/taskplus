// npm run seed: departments, teams, people and the reporting line from Ornate Samanvay. Safe to run again (updates in place).
// Phone numbers are made up (98000 000xx). Everyone gets SEED_PASSWORD as a starting password (only if they have none yet).
import { fileURLToPath } from 'node:url';
import { loadEnv } from '../config/env';
import { hashPassword } from '../modules/auth/routes';
import { createDb, type Db } from './client';
import type { Role } from './schema';

interface SeedUser { name: string; phone: string; dept: string | null; team?: string; role: Role; reportsTo?: string }

export const SEED = {
  departments: [
    { name: 'Support', modules: ['Profit NX', 'SQL Installation', 'Licensing', 'Printing', 'Other'], teams: ['Support'] },
    { name: 'Development', modules: ['Profit NX', 'Ornate', 'Power BI', 'Mobile App', 'Other'], teams: ['ProfitNX', 'Ornate', 'PowerBI'] },
    { name: 'Sales', modules: ['Demo Request', 'Quotation', 'Renewal', 'New License', 'Other'], teams: ['Sales'] },
    { name: 'HR', modules: ['Payroll', 'Leave', 'Attendance', 'Onboarding', 'Other'], teams: ['HR'] },
  ],
  /** Team leads lead the team named in `team`; `reportsTo` is the lead above them. */
  users: [
    { name: 'Support Lead', phone: '9800000001', dept: 'Support', team: 'Support', role: 'dept_head' },
    { name: 'Riya Shah', phone: '9800000002', dept: 'Support', team: 'Support', role: 'staff' },
    { name: 'Karan Patel', phone: '9800000003', dept: 'Support', team: 'Support', role: 'staff' },
    { name: 'Tushar Parmar', phone: '9800000004', dept: 'Development', team: 'Ornate', role: 'dept_head' },
    { name: 'Dhaval Dalsania', phone: '9800000005', dept: 'Development', team: 'ProfitNX', role: 'team_lead', reportsTo: '9800000004' },
    { name: 'Vishwas', phone: '9800000006', dept: 'Development', team: 'PowerBI', role: 'team_lead', reportsTo: '9800000005' },
    { name: 'Nisha Patel', phone: '9800000007', dept: 'Development', team: 'PowerBI', role: 'staff' },
    { name: 'Sales Lead', phone: '9800000008', dept: 'Sales', team: 'Sales', role: 'dept_head' },
    { name: 'Priya Nair', phone: '9800000009', dept: 'Sales', team: 'Sales', role: 'staff' },
    { name: 'Admin', phone: '9800000010', dept: null, role: 'admin' },
    { name: 'Kunal Mehta', phone: '9800000011', dept: 'Development', team: 'ProfitNX', role: 'staff' },
    { name: 'Amit Vora', phone: '9800000012', dept: 'Development', team: 'Ornate', role: 'staff' },
    { name: 'Pooja Desai', phone: '9800000013', dept: 'Development', team: 'Ornate', role: 'staff' },
    { name: 'HR Lead', phone: '9800000014', dept: 'HR', team: 'HR', role: 'dept_head' },
    { name: 'HR Staff', phone: '9800000015', dept: 'HR', team: 'HR', role: 'staff' },
  ] as SeedUser[],
};

export async function seed(db: Db, password = process.env.SEED_PASSWORD) {
  const deptIds = new Map<string, string>(), teamIds = new Map<string, string>(), userIds = new Map<string, string>();
  for (const d of SEED.departments) {
    const found = await db.selectFrom('departments').select('id').where('name', '=', d.name).executeTakeFirst();
    const id = found?.id ?? (await db.insertInto('departments').values({ name: d.name, modules: JSON.stringify(d.modules) })
      .output('inserted.id').executeTakeFirstOrThrow()).id;
    deptIds.set(d.name, id);
    for (const t of d.teams) {
      const ft = await db.selectFrom('teams').select('id').where('department_id', '=', id).where('name', '=', t).executeTakeFirst();
      teamIds.set(`${d.name}/${t}`, ft?.id ?? (await db.insertInto('teams').values({ department_id: id, name: t, lead_id: null }).output('inserted.id').executeTakeFirstOrThrow()).id);
    }
  }
  for (const u of SEED.users) {
    const found = await db.selectFrom('users').select(['id', 'password_hash']).where('phone', '=', u.phone).executeTakeFirst();
    const fields = {
      name: u.name, role: u.role, department_id: u.dept ? deptIds.get(u.dept)! : null,
      team_id: u.dept && u.team ? teamIds.get(`${u.dept}/${u.team}`)! : null,
    };
    let id = found?.id;
    if (id) await db.updateTable('users').set(fields).where('id', '=', id).execute();
    else id = (await db.insertInto('users').values({ ...fields, phone: u.phone }).output('inserted.id').executeTakeFirstOrThrow()).id;
    userIds.set(u.phone, id);
    if (password && !found?.password_hash) await db.updateTable('users').set(await hashPassword(password)).where('id', '=', id).execute();
  }
  for (const u of SEED.users) {
    const id = userIds.get(u.phone)!;
    await db.updateTable('users').set({ reports_to_id: u.reportsTo ? userIds.get(u.reportsTo)! : null }).where('id', '=', id).execute();
    if (u.role === 'dept_head' && u.dept) await db.updateTable('departments').set({ head_user_id: id }).where('id', '=', deptIds.get(u.dept)!).execute();
    // Department heads and team leads lead the team they sit in.
    if ((u.role === 'dept_head' || u.role === 'team_lead') && u.dept && u.team)
      await db.updateTable('teams').set({ lead_id: id }).where('id', '=', teamIds.get(`${u.dept}/${u.team}`)!).execute();
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const db = createDb(loadEnv().DATABASE_URL);
  try { await seed(db); console.log(`Seeded ${SEED.departments.length} departments and ${SEED.users.length} people.`); } finally { await db.destroy(); }
}
