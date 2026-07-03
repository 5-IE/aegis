import { RowDataPacket } from 'mysql2';
import { pool } from '../pool.js';

export interface SystemConfigRow {
  key: string;
  value: string;
  updated_at: Date;
}

export async function getAllSystemConfig(): Promise<SystemConfigRow[]> {
  const [rows] = await pool.query<(SystemConfigRow & RowDataPacket)[]>(
    'SELECT `key`, `value`, `updated_at` FROM `SYSTEM_CONFIG`',
  );
  return rows;
}

export async function upsertSystemConfig(key: string, value: string): Promise<void> {
  await pool.query(
    'INSERT INTO `SYSTEM_CONFIG` (`key`, `value`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)',
    [key, value],
  );
}
