import { RowDataPacket, ResultSetHeader } from 'mysql2';
import { pool } from '../pool.js';

export interface UserRow {
  id_user: number;
  username: string;
  password: string;
  email: string;
  role: 'admin' | 'learner';
  first_name: string | null;
  last_name: string | null;
  session: 'AM' | 'PM';
  is_active: boolean;
  created_at: Date;
}

export async function findUserByUsername(username: string): Promise<UserRow | null> {
  const [rows] = await pool.query<(UserRow & RowDataPacket)[]>(
    'SELECT * FROM `USER` WHERE `username` = ? AND `is_active` = TRUE LIMIT 1',
    [username],
  );
  return rows[0] ?? null;
}

export async function findUserByUsernameAnyState(username: string): Promise<UserRow | null> {
  const [rows] = await pool.query<(UserRow & RowDataPacket)[]>(
    'SELECT * FROM `USER` WHERE `username` = ? LIMIT 1',
    [username],
  );
  return rows[0] ?? null;
}

export async function findUserById(id: number): Promise<UserRow | null> {
  const [rows] = await pool.query<(UserRow & RowDataPacket)[]>(
    'SELECT * FROM `USER` WHERE `id_user` = ? AND `is_active` = TRUE LIMIT 1',
    [id],
  );
  return rows[0] ?? null;
}

export async function findUserByIdAnyState(id: number): Promise<UserRow | null> {
  const [rows] = await pool.query<(UserRow & RowDataPacket)[]>(
    'SELECT * FROM `USER` WHERE `id_user` = ? LIMIT 1',
    [id],
  );
  return rows[0] ?? null;
}

export async function findUserByEmailActive(email: string): Promise<UserRow | null> {
  const [rows] = await pool.query<(UserRow & RowDataPacket)[]>(
    'SELECT * FROM `USER` WHERE `email` = ? AND `is_active` = TRUE LIMIT 1',
    [email],
  );
  return rows[0] ?? null;
}

export async function insertUser(input: {
  username: string;
  passwordHash: string;
  email: string;
  role: 'admin' | 'learner';
  firstName?: string;
  lastName?: string;
  session?: 'AM' | 'PM';
}): Promise<number> {
  const [result] = await pool.query<ResultSetHeader>(
    `INSERT INTO \`USER\`
       (\`username\`, \`password\`, \`email\`, \`role\`, \`first_name\`, \`last_name\`, \`session\`)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    [
      input.username,
      input.passwordHash,
      input.email,
      input.role,
      input.firstName ?? null,
      input.lastName ?? null,
      input.session ?? 'AM',
    ],
  );
  return result.insertId;
}

export async function listLearners(
  filter: { name?: string; session?: 'AM' | 'PM' },
  page: number,
  perPage: number,
): Promise<{ list: UserRow[]; total: number }> {
  const conds: string[] = [`\`role\` = 'learner'`, '`is_active` = TRUE'];
  const params: unknown[] = [];
  if (filter.name !== undefined && filter.name !== '') {
    conds.push(`TRIM(CONCAT_WS(' ', \`first_name\`, \`last_name\`)) LIKE ?`);
    params.push(`%${filter.name}%`);
  }
  if (filter.session !== undefined) {
    conds.push('`session` = ?');
    params.push(filter.session);
  }
  const where = 'WHERE ' + conds.join(' AND ');

  const [countRows] = await pool.query<({ c: number } & RowDataPacket)[]>(
    `SELECT COUNT(*) AS c FROM \`USER\` ${where}`,
    params,
  );
  const total = countRows[0]?.c ?? 0;

  const offset = (page - 1) * perPage;
  const [rows] = await pool.query<(UserRow & RowDataPacket)[]>(
    `SELECT * FROM \`USER\` ${where} ORDER BY \`first_name\` ASC, \`last_name\` ASC LIMIT ? OFFSET ?`,
    [...params, perPage, offset],
  );
  return { list: rows, total };
}

export async function listLearnerIds(): Promise<number[]> {
  const [rows] = await pool.query<({ id_user: number } & RowDataPacket)[]>(
    "SELECT `id_user` FROM `USER` WHERE `role` = 'learner' AND `is_active` = TRUE",
  );
  return rows.map((r) => r.id_user);
}

export async function countLearners(): Promise<number> {
  const [rows] = await pool.query<({ c: number } & RowDataPacket)[]>(
    "SELECT COUNT(*) AS c FROM `USER` WHERE `role` = 'learner' AND `is_active` = TRUE",
  );
  return rows[0]?.c ?? 0;
}

export async function listUsers(
  filter: { role?: 'admin' | 'learner'; session?: 'AM' | 'PM'; name?: string; includeInactive?: boolean },
  page: number,
  perPage: number,
): Promise<{ list: UserRow[]; total: number }> {
  const conds: string[] = [];
  const params: unknown[] = [];
  if (!filter.includeInactive) {
    conds.push('`is_active` = TRUE');
  }
  if (filter.role !== undefined) {
    conds.push('`role` = ?');
    params.push(filter.role);
  }
  if (filter.session !== undefined) {
    conds.push('`session` = ?');
    params.push(filter.session);
  }
  if (filter.name !== undefined && filter.name !== '') {
    conds.push(`TRIM(CONCAT_WS(' ', \`first_name\`, \`last_name\`)) LIKE ?`);
    params.push(`%${filter.name}%`);
  }
  const where = conds.length > 0 ? 'WHERE ' + conds.join(' AND ') : '';

  const [countRows] = await pool.query<({ c: number } & RowDataPacket)[]>(
    `SELECT COUNT(*) AS c FROM \`USER\` ${where}`,
    params,
  );
  const total = countRows[0]?.c ?? 0;

  const offset = (page - 1) * perPage;
  const [rows] = await pool.query<(UserRow & RowDataPacket)[]>(
    `SELECT * FROM \`USER\` ${where}
     ORDER BY \`first_name\` ASC, \`last_name\` ASC, \`id_user\` ASC
     LIMIT ? OFFSET ?`,
    [...params, perPage, offset],
  );
  return { list: rows, total };
}

export async function updateUserFields(
  id: number,
  patch: {
    email?: string;
    role?: 'admin' | 'learner';
    session?: 'AM' | 'PM';
    first_name?: string | null;
    last_name?: string | null;
  },
): Promise<void> {
  const sets: string[] = [];
  const params: unknown[] = [];
  if (patch.email !== undefined) {
    sets.push('`email` = ?');
    params.push(patch.email);
  }
  if (patch.role !== undefined) {
    sets.push('`role` = ?');
    params.push(patch.role);
  }
  if (patch.session !== undefined) {
    sets.push('`session` = ?');
    params.push(patch.session);
  }
  if (patch.first_name !== undefined) {
    sets.push('`first_name` = ?');
    params.push(patch.first_name);
  }
  if (patch.last_name !== undefined) {
    sets.push('`last_name` = ?');
    params.push(patch.last_name);
  }
  if (sets.length === 0) return;
  params.push(id);
  await pool.query(
    `UPDATE \`USER\` SET ${sets.join(', ')} WHERE \`id_user\` = ?`,
    params,
  );
}

export async function updateUserPassword(id: number, passwordHash: string): Promise<void> {
  await pool.query(
    'UPDATE `USER` SET `password` = ? WHERE `id_user` = ?',
    [passwordHash, id],
  );
}

export async function softDeleteUser(id: number): Promise<void> {
  await pool.query(
    'UPDATE `USER` SET `is_active` = FALSE WHERE `id_user` = ?',
    [id],
  );
}

export async function reactivateUser(id: number): Promise<void> {
  await pool.query(
    'UPDATE `USER` SET `is_active` = TRUE WHERE `id_user` = ?',
    [id],
  );
}

export async function countActiveAdmins(): Promise<number> {
  const [rows] = await pool.query<({ c: number } & RowDataPacket)[]>(
    "SELECT COUNT(*) AS c FROM `USER` WHERE `role` = 'admin' AND `is_active` = TRUE",
  );
  return rows[0]?.c ?? 0;
}
