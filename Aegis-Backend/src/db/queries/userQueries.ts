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
}

export async function findUserByUsername(username: string): Promise<UserRow | null> {
  const [rows] = await pool.query<(UserRow & RowDataPacket)[]>(
    'SELECT * FROM `USER` WHERE `username` = ? LIMIT 1',
    [username],
  );
  return rows[0] ?? null;
}

export async function findUserById(id: number): Promise<UserRow | null> {
  const [rows] = await pool.query<(UserRow & RowDataPacket)[]>(
    'SELECT * FROM `USER` WHERE `id_user` = ? LIMIT 1',
    [id],
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
  const conds: string[] = [`\`role\` = 'learner'`];
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
    "SELECT `id_user` FROM `USER` WHERE `role` = 'learner'",
  );
  return rows.map((r) => r.id_user);
}

export async function countLearners(): Promise<number> {
  const [rows] = await pool.query<({ c: number } & RowDataPacket)[]>(
    "SELECT COUNT(*) AS c FROM `USER` WHERE `role` = 'learner'",
  );
  return rows[0]?.c ?? 0;
}
