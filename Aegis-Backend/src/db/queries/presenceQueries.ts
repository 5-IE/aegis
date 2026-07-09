import { RowDataPacket, ResultSetHeader } from 'mysql2';
import { pool } from '../pool.js';
import { logger } from '../../lib/logger.js';

export interface PresenceLogRow {
  id_log: number;
  id_user: number;
  id_room: number;
  timestamp: Date;
  position_x: number | null;
  position_y: number | null;
  battery_level: number | null;
}

export async function insertPresenceLog(input: {
  userId: number;
  roomId: number;
  positionX: number | null;
  positionY: number | null;
  batteryLevel: number | null;
}): Promise<void> {
  const [result] = await pool.query<ResultSetHeader>(
    `INSERT INTO \`PRESENCE_LOG\` (\`id_user\`, \`id_room\`, \`position_x\`, \`position_y\`, \`battery_level\`)
     VALUES (?, ?, ?, ?, ?)`,
    [input.userId, input.roomId, input.positionX, input.positionY, input.batteryLevel],
  );
  // Prove the write landed: insertId + affectedRows are exactly what MySQL
  // committed. If this logs affectedRows:1 but the row is "missing", the query
  // ran against a different DB/host than the one being inspected.
  logger.info(
    {
      table: 'PRESENCE_LOG',
      insertId: result.insertId,
      affectedRows: result.affectedRows,
      userId: input.userId,
      roomId: input.roomId,
    },
    'presence.insert',
  );
}

export async function firstPingForUserInWindow(userId: number, startUtc: Date, endUtc: Date): Promise<Date | null> {
  const [rows] = await pool.query<({ ts: Date } & RowDataPacket)[]>(
    'SELECT MIN(`timestamp`) AS ts FROM `PRESENCE_LOG` WHERE `id_user` = ? AND `timestamp` >= ? AND `timestamp` < ?',
    [userId, startUtc, endUtc],
  );
  return rows[0]?.ts ?? null;
}

export async function lastPingForUserInWindow(userId: number, startUtc: Date, endUtc: Date): Promise<Date | null> {
  const [rows] = await pool.query<({ ts: Date } & RowDataPacket)[]>(
    'SELECT MAX(`timestamp`) AS ts FROM `PRESENCE_LOG` WHERE `id_user` = ? AND `timestamp` >= ? AND `timestamp` < ?',
    [userId, startUtc, endUtc],
  );
  return rows[0]?.ts ?? null;
}

export async function firstAndLastPingBulk(
  userIds: number[],
  startUtc: Date,
  endUtc: Date,
): Promise<Map<number, { first: Date; last: Date }>> {
  const out = new Map<number, { first: Date; last: Date }>();
  if (userIds.length === 0) return out;
  const [rows] = await pool.query<({ id_user: number; first: Date; last: Date } & RowDataPacket)[]>(
    `SELECT \`id_user\`, MIN(\`timestamp\`) AS first, MAX(\`timestamp\`) AS last
     FROM \`PRESENCE_LOG\`
     WHERE \`id_user\` IN (?) AND \`timestamp\` >= ? AND \`timestamp\` < ?
     GROUP BY \`id_user\``,
    [userIds, startUtc, endUtc],
  );
  for (const r of rows) out.set(r.id_user, { first: r.first, last: r.last });
  return out;
}

export interface CurrentRoomRow {
  id_user: number;
  id_room: number;
  last_seen: Date;
  position_x: number | null;
  position_y: number | null;
  log_id: number;
}

export async function currentRoomPerUser(
  startUtc: Date,
  endUtc: Date,
  stalenessSince: Date,
): Promise<CurrentRoomRow[]> {
  // Latest log per user in the day-window; only include if that latest is >= stalenessSince.
  const [rows] = await pool.query<(CurrentRoomRow & RowDataPacket)[]>(
    `SELECT p.\`id_user\`, p.\`id_room\`, p.\`timestamp\` AS last_seen,
            p.\`position_x\`, p.\`position_y\`, p.\`id_log\` AS log_id
     FROM \`PRESENCE_LOG\` p
     INNER JOIN (
       SELECT \`id_user\`, MAX(\`timestamp\`) AS max_ts
       FROM \`PRESENCE_LOG\`
       WHERE \`timestamp\` >= ? AND \`timestamp\` < ?
       GROUP BY \`id_user\`
     ) latest ON latest.\`id_user\` = p.\`id_user\` AND latest.max_ts = p.\`timestamp\`
     WHERE p.\`timestamp\` >= ?`,
    [startUtc, endUtc, stalenessSince],
  );
  return rows;
}

export async function countPresenceLogsForRoom(roomId: number): Promise<number> {
  const [rows] = await pool.query<({ c: number } & RowDataPacket)[]>(
    'SELECT COUNT(*) AS c FROM `PRESENCE_LOG` WHERE `id_room` = ?',
    [roomId],
  );
  return rows[0]?.c ?? 0;
}
