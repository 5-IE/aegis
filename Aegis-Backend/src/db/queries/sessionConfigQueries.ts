import { RowDataPacket } from 'mysql2';
import { pool } from '../pool.js';

export interface SessionConfigRow {
  session: 'AM' | 'PM';
  start_time: string;
  late_after: string;
  end_time: string;
  updated_at: Date;
}

export async function getAllSessionConfigs(): Promise<SessionConfigRow[]> {
  const [rows] = await pool.query<(SessionConfigRow & RowDataPacket)[]>(
    'SELECT `session`, `start_time`, `late_after`, `end_time`, `updated_at` FROM `SESSION_CONFIG` ORDER BY `session`',
  );
  return rows;
}

export async function getSessionConfig(session: 'AM' | 'PM'): Promise<SessionConfigRow | null> {
  const [rows] = await pool.query<(SessionConfigRow & RowDataPacket)[]>(
    'SELECT `session`, `start_time`, `late_after`, `end_time`, `updated_at` FROM `SESSION_CONFIG` WHERE `session` = ? LIMIT 1',
    [session],
  );
  return rows[0] ?? null;
}

export async function updateSessionConfig(
  session: 'AM' | 'PM',
  input: { start_time: string; late_after: string; end_time: string },
): Promise<void> {
  await pool.query(
    'UPDATE `SESSION_CONFIG` SET `start_time` = ?, `late_after` = ?, `end_time` = ? WHERE `session` = ?',
    [input.start_time, input.late_after, input.end_time, session],
  );
}
