import { RowDataPacket } from 'mysql2';
import { pool } from '../pool.js';

export interface AttendanceReportRow {
  id_user: number;
  date: string;
  status: 'early' | 'late' | 'leave' | 'absent';
  session: 'AM' | 'PM';
  name: string;
}

export async function attendanceRecordsInRange(
  from: string,
  to: string,
  filter: { session?: 'AM' | 'PM'; userId?: number },
): Promise<AttendanceReportRow[]> {
  const conds: string[] = ['ah.`date` >= ?', 'ah.`date` <= ?'];
  const params: unknown[] = [from, to];
  if (filter.session !== undefined) {
    conds.push('u.`session` = ?');
    params.push(filter.session);
  }
  if (filter.userId !== undefined) {
    conds.push('ah.`id_user` = ?');
    params.push(filter.userId);
  }
  const where = 'WHERE ' + conds.join(' AND ');

  const [rows] = await pool.query<(AttendanceReportRow & RowDataPacket)[]>(
    `SELECT ah.\`id_user\`, DATE_FORMAT(ah.\`date\`, "%Y-%m-%d") AS \`date\`, ah.\`status\`,
            u.\`session\`,
            COALESCE(NULLIF(TRIM(CONCAT_WS(' ', u.\`first_name\`, u.\`last_name\`)), ''), u.\`username\`) AS \`name\`
     FROM \`ATTENDANCE_HISTORY\` ah
     INNER JOIN \`USER\` u ON u.\`id_user\` = ah.\`id_user\`
     ${where}
     ORDER BY ah.\`date\` ASC, \`name\` ASC, ah.\`id_user\` ASC`,
    params,
  );
  return rows;
}

export interface LearnerAggregateRow {
  id_user: number;
  session: 'AM' | 'PM';
  name: string;
  present: number;
  late: number;
  absent: number;
}

export async function attendanceAggregatesInRange(
  from: string,
  to: string,
  filter: { session?: 'AM' | 'PM'; userId?: number },
): Promise<{ perLearner: LearnerAggregateRow[]; daysWithSessions: number }> {
  const conds: string[] = ['ah.`date` >= ?', 'ah.`date` <= ?'];
  const params: unknown[] = [from, to];
  if (filter.session !== undefined) {
    conds.push('u.`session` = ?');
    params.push(filter.session);
  }
  if (filter.userId !== undefined) {
    conds.push('ah.`id_user` = ?');
    params.push(filter.userId);
  }
  const where = 'WHERE ' + conds.join(' AND ');

  const [rows] = await pool.query<(LearnerAggregateRow & RowDataPacket)[]>(
    `SELECT ah.\`id_user\`, u.\`session\`,
            COALESCE(NULLIF(TRIM(CONCAT_WS(' ', u.\`first_name\`, u.\`last_name\`)), ''), u.\`username\`) AS \`name\`,
            COUNT(CASE WHEN ah.\`status\` IN ('early', 'late') THEN 1 END) AS \`present\`,
            COUNT(CASE WHEN ah.\`status\` = 'late' THEN 1 END) AS \`late\`,
            COUNT(CASE WHEN ah.\`status\` = 'absent' THEN 1 END) AS \`absent\`
     FROM \`ATTENDANCE_HISTORY\` ah
     INNER JOIN \`USER\` u ON u.\`id_user\` = ah.\`id_user\`
     ${where}
     GROUP BY ah.\`id_user\`, u.\`session\`, \`name\`
     ORDER BY \`name\` ASC, ah.\`id_user\` ASC`,
    params,
  );

  const [countRows] = await pool.query<({ c: number } & RowDataPacket)[]>(
    `SELECT COUNT(DISTINCT ah.\`date\`) AS c
     FROM \`ATTENDANCE_HISTORY\` ah
     INNER JOIN \`USER\` u ON u.\`id_user\` = ah.\`id_user\`
     ${where}`,
    params,
  );

  return { perLearner: rows, daysWithSessions: countRows[0]?.c ?? 0 };
}

export interface DayWindow {
  date: string;
  startUtc: Date;
  endUtc: Date;
}

// First/last presence ping per (local date, user), where each local date maps to
// a UTC window computed by the caller (so DST transitions are handled per-day).
export async function firstLastPingsByLocalDay(
  windows: DayWindow[],
  userIds: number[],
): Promise<Map<string, { first: Date; last: Date }>> {
  const out = new Map<string, { first: Date; last: Date }>();
  if (windows.length === 0 || userIds.length === 0) return out;

  const unionParts = windows.map((_, i) =>
    i === 0
      ? 'SELECT ? AS `date`, ? AS `start_utc`, ? AS `end_utc`'
      : 'SELECT ?, ?, ?',
  );
  const windowParams = windows.flatMap((w) => [w.date, w.startUtc, w.endUtc]);

  const [rows] = await pool.query<({ date: string; id_user: number; first: Date; last: Date } & RowDataPacket)[]>(
    `SELECT w.\`date\`, p.\`id_user\`, MIN(p.\`timestamp\`) AS first, MAX(p.\`timestamp\`) AS last
     FROM \`PRESENCE_LOG\` p
     INNER JOIN (${unionParts.join(' UNION ALL ')}) w
       ON p.\`timestamp\` >= w.\`start_utc\` AND p.\`timestamp\` < w.\`end_utc\`
     WHERE p.\`id_user\` IN (?)
     GROUP BY w.\`date\`, p.\`id_user\``,
    [...windowParams, userIds],
  );
  for (const r of rows) out.set(`${r.date}|${r.id_user}`, { first: r.first, last: r.last });
  return out;
}
