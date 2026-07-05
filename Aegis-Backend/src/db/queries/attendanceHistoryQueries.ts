import { RowDataPacket } from 'mysql2';
import { pool } from '../pool.js';

export interface AttendanceHistoryRow {
  id_user: number;
  date: string;
  status: 'early' | 'late' | 'leave' | 'absent';
}

export async function countByStatus(userId: number): Promise<{ early: number; late: number; leave: number }> {
  const [rows] = await pool.query<({ status: string; c: number } & RowDataPacket)[]>(
    'SELECT `status`, COUNT(*) AS c FROM `ATTENDANCE_HISTORY` WHERE `id_user` = ? GROUP BY `status`',
    [userId],
  );
  const out = { early: 0, late: 0, leave: 0 };
  for (const r of rows) {
    if (r.status === 'early') out.early = r.c;
    else if (r.status === 'late') out.late = r.c;
    else if (r.status === 'leave') out.leave = r.c;
  }
  return out;
}

export async function findByUserAndDate(userId: number, date: string): Promise<AttendanceHistoryRow | null> {
  const [rows] = await pool.query<(AttendanceHistoryRow & RowDataPacket)[]>(
    'SELECT `id_user`, DATE_FORMAT(`date`, "%Y-%m-%d") AS `date`, `status` FROM `ATTENDANCE_HISTORY` WHERE `id_user` = ? AND `date` = ? LIMIT 1',
    [userId, date],
  );
  return rows[0] ?? null;
}

export async function upsertAttendanceHistory(
  userId: number,
  date: string,
  status: AttendanceHistoryRow['status'],
): Promise<void> {
  await pool.query(
    `INSERT INTO \`ATTENDANCE_HISTORY\` (\`id_user\`, \`date\`, \`status\`)
     VALUES (?, ?, ?)
     ON DUPLICATE KEY UPDATE \`status\` = VALUES(\`status\`)`,
    [userId, date, status],
  );
}

export async function listHistoriesByUser(
  userId: number,
  filter: { month?: number; year?: number },
  page: number,
  perPage: number,
): Promise<{ list: AttendanceHistoryRow[]; total: number }> {
  const offset = (page - 1) * perPage;
  const conds: string[] = ['`id_user` = ?'];
  const params: unknown[] = [userId];
  if (filter.year !== undefined) {
    conds.push('YEAR(`date`) = ?');
    params.push(filter.year);
  }
  if (filter.month !== undefined) {
    conds.push('MONTH(`date`) = ?');
    params.push(filter.month);
  }
  const where = 'WHERE ' + conds.join(' AND ');

  const [countRows] = await pool.query<({ c: number } & RowDataPacket)[]>(
    `SELECT COUNT(*) AS c FROM \`ATTENDANCE_HISTORY\` ${where}`,
    params,
  );
  const total = countRows[0]?.c ?? 0;

  const [rows] = await pool.query<(AttendanceHistoryRow & RowDataPacket)[]>(
    `SELECT \`id_user\`, DATE_FORMAT(\`date\`, "%Y-%m-%d") AS \`date\`, \`status\`
     FROM \`ATTENDANCE_HISTORY\`
     ${where}
     ORDER BY \`date\` DESC
     LIMIT ? OFFSET ?`,
    [...params, perPage, offset],
  );

  return { list: rows, total };
}
