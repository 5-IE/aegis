import { RowDataPacket, ResultSetHeader } from 'mysql2';
import { pool } from '../pool.js';

export interface RefreshTokenRow {
  id_token: number;
  id_user: number;
  token_hash: string;
  expires_at: Date;
  revoked_at: Date | null;
  replaced_by_id: number | null;
  created_at: Date;
}

export async function insertRefreshToken(input: {
  userId: number;
  tokenHash: string;
  expiresAt: Date;
}): Promise<number> {
  const [result] = await pool.query<ResultSetHeader>(
    `INSERT INTO \`REFRESH_TOKEN\` (\`id_user\`, \`token_hash\`, \`expires_at\`)
     VALUES (?, ?, ?)`,
    [input.userId, input.tokenHash, input.expiresAt],
  );
  return result.insertId;
}

export async function findRefreshTokenByHash(hash: string): Promise<RefreshTokenRow | null> {
  const [rows] = await pool.query<(RefreshTokenRow & RowDataPacket)[]>(
    'SELECT * FROM `REFRESH_TOKEN` WHERE `token_hash` = ? LIMIT 1',
    [hash],
  );
  return rows[0] ?? null;
}

export async function revokeRefreshToken(id: number, replacedById: number | null): Promise<void> {
  await pool.query(
    'UPDATE `REFRESH_TOKEN` SET `revoked_at` = NOW(), `replaced_by_id` = ? WHERE `id_token` = ? AND `revoked_at` IS NULL',
    [replacedById, id],
  );
}

export async function revokeAllRefreshTokensForUser(userId: number): Promise<void> {
  await pool.query(
    'UPDATE `REFRESH_TOKEN` SET `revoked_at` = NOW() WHERE `id_user` = ? AND `revoked_at` IS NULL',
    [userId],
  );
}
