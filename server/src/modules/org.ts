// Organisation rules from Ornate Samanvay: teams, team leads and the reporting line.
import type { Db } from '../db/client';
import type { User } from '../db/schema';

export interface OrgSnapshot {
  users: Pick<User, 'id' | 'name' | 'role' | 'department_id' | 'team_id' | 'reports_to_id' | 'is_active'>[];
  teams: { id: string; department_id: string; name: string; lead_id: string | null }[];
  departments: { id: string; name: string; head_user_id: string | null }[];
}

/** One read of the (small) organisation; the rules below are pure functions over it. */
export async function loadOrg(db: Db): Promise<OrgSnapshot> {
  const [users, teams, departments] = await Promise.all([
    db.selectFrom('users').select(['id', 'name', 'role', 'department_id', 'team_id', 'reports_to_id', 'is_active']).execute(),
    db.selectFrom('teams').select(['id', 'department_id', 'name', 'lead_id']).execute(),
    db.selectFrom('departments').select(['id', 'name', 'head_user_id']).execute(),
  ]);
  return { users, teams, departments };
}

/** Teams a person looks after: a department head, every team in the department; a team lead, their own
 *  team plus every team whose lead reports to them (and so on down). Staff: none. */
export function teamsLedBy(org: OrgSnapshot, userId: string): string[] {
  const u = org.users.find((x) => x.id === userId);
  if (!u) return [];
  if (u.role === 'dept_head') return org.teams.filter((t) => t.department_id === u.department_id).map((t) => t.id);
  if (u.role !== 'team_lead') return [];
  const out = new Set(org.teams.filter((t) => t.lead_id === userId).map((t) => t.id));
  for (const t of org.teams) {
    const lead = t.lead_id ? org.users.find((x) => x.id === t.lead_id) : undefined;
    if (lead?.reports_to_id === userId) for (const id of teamsLedBy(org, lead.id)) out.add(id);
  }
  return [...out];
}

/** The people above someone: their team's lead, then each lead's reporting manager, then the department head. */
export function leadChain(org: OrgSnapshot, userId: string): string[] {
  const u = org.users.find((x) => x.id === userId);
  if (!u) return [];
  const chain: string[] = [];
  const team = org.teams.find((t) => t.id === u.team_id);
  let next: string | null | undefined = team?.lead_id && team.lead_id !== userId ? team.lead_id : u.reports_to_id;
  while (next && !chain.includes(next)) {
    chain.push(next);
    next = org.users.find((x) => x.id === next)?.reports_to_id;
  }
  const head = org.departments.find((d) => d.id === u.department_id)?.head_user_id;
  if (head && head !== userId && !chain.includes(head)) chain.push(head);
  return chain;
}

/** Short label, e.g. "ProfitNX lead", "Development head", "PowerBI team". */
export function roleLabel(org: OrgSnapshot, userId: string): string {
  const u = org.users.find((x) => x.id === userId);
  if (!u) return '';
  const team = org.teams.find((t) => t.id === u.team_id)?.name;
  const dept = org.departments.find((d) => d.id === u.department_id)?.name;
  if (u.role === 'admin') return 'Admin';
  if (u.role === 'dept_head') return `${dept ?? ''} head`.trim();
  if (u.role === 'team_lead') return `${team ?? dept ?? ''} lead`.trim();
  return team ? `${team} team` : dept ?? '';
}

/** May `me` move work to or from `userId`? Department head of their department, or a lead whose teams include theirs. */
export function manages(org: OrgSnapshot, meId: string, userId: string): boolean {
  const me = org.users.find((x) => x.id === meId), u = org.users.find((x) => x.id === userId);
  if (!me || !u) return false;
  if (me.role === 'dept_head') return me.department_id === u.department_id;
  return !!u.team_id && teamsLedBy(org, meId).includes(u.team_id);
}

/** People who receive a team's new work: its members (including its lead). */
export const teamMembers = (org: OrgSnapshot, teamId: string) =>
  org.users.filter((u) => u.team_id === teamId && u.is_active).map((u) => u.id);
