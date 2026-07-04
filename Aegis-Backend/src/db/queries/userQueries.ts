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
