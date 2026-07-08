import { RowDataPacket, ResultSetHeader } from 'mysql2';
import { pool } from '../pool.js';

export interface DeviceWithRoom {
  id_device: number;
  name: string;
  identifier: string;
  id_room: number | null;
  position_x: number | null;
  position_y: number | null;
  room_name: string | null;
}

const SELECT_DEVICE = `
  SELECT d.\`id_device\`, d.\`name\`, d.\`identifier\`, d.\`id_room\`,
         d.\`position_x\`, d.\`position_y\`, r.\`name\` AS room_name
  FROM \`DEVICE\` d
  LEFT JOIN \`ROOM\` r ON r.\`id_room\` = d.\`id_room\`
`;

export async function listAssignedDevices(): Promise<DeviceWithRoom[]> {
  const [rows] = await pool.query<(DeviceWithRoom & RowDataPacket)[]>(
    `${SELECT_DEVICE}
     WHERE d.\`id_room\` IS NOT NULL
     ORDER BY d.\`id_device\` ASC`,
  );
  return rows;
}

export async function listDevices(
  filter: { assigned?: boolean; roomId?: number },
  page: number,
  perPage: number,
): Promise<{ list: DeviceWithRoom[]; total: number }> {
  const conds: string[] = [];
  const params: unknown[] = [];
  if (filter.assigned === true) conds.push('d.`id_room` IS NOT NULL');
  else if (filter.assigned === false) conds.push('d.`id_room` IS NULL');
  if (filter.roomId !== undefined) {
    conds.push('d.`id_room` = ?');
    params.push(filter.roomId);
  }
  const where = conds.length > 0 ? 'WHERE ' + conds.join(' AND ') : '';

  const [countRows] = await pool.query<({ c: number } & RowDataPacket)[]>(
    `SELECT COUNT(*) AS c FROM \`DEVICE\` d ${where}`,
    params,
  );
  const total = countRows[0]?.c ?? 0;

  const offset = (page - 1) * perPage;
  const [rows] = await pool.query<(DeviceWithRoom & RowDataPacket)[]>(
    `${SELECT_DEVICE} ${where} ORDER BY d.\`id_device\` ASC LIMIT ? OFFSET ?`,
    [...params, perPage, offset],
  );
  return { list: rows, total };
}

export async function findDeviceById(id: number): Promise<DeviceWithRoom | null> {
  const [rows] = await pool.query<(DeviceWithRoom & RowDataPacket)[]>(
    `${SELECT_DEVICE} WHERE d.\`id_device\` = ? LIMIT 1`,
    [id],
  );
  return rows[0] ?? null;
}

export async function findDeviceByIdentifier(identifier: string): Promise<DeviceWithRoom | null> {
  const [rows] = await pool.query<(DeviceWithRoom & RowDataPacket)[]>(
    `${SELECT_DEVICE} WHERE d.\`identifier\` = ? LIMIT 1`,
    [identifier],
  );
  return rows[0] ?? null;
}

export async function insertDevice(input: {
  name: string;
  identifier: string;
  id_room: number | null;
  position_x?: number | null;
  position_y?: number | null;
}): Promise<number> {
  const [result] = await pool.query<ResultSetHeader>(
    'INSERT INTO `DEVICE` (`name`, `identifier`, `id_room`, `position_x`, `position_y`) VALUES (?, ?, ?, ?, ?)',
    [input.name, input.identifier, input.id_room, input.position_x ?? null, input.position_y ?? null],
  );
  return result.insertId;
}

export async function updateDevice(
  id: number,
  patch: {
    name?: string;
    identifier?: string;
    id_room?: number | null;
    position_x?: number | null;
    position_y?: number | null;
  },
): Promise<void> {
  const sets: string[] = [];
  const params: unknown[] = [];
  if (patch.name !== undefined) {
    sets.push('`name` = ?');
    params.push(patch.name);
  }
  if (patch.identifier !== undefined) {
    sets.push('`identifier` = ?');
    params.push(patch.identifier);
  }
  if (patch.id_room !== undefined) {
    sets.push('`id_room` = ?');
    params.push(patch.id_room);
  }
  if (patch.position_x !== undefined) {
    sets.push('`position_x` = ?');
    params.push(patch.position_x);
  }
  if (patch.position_y !== undefined) {
    sets.push('`position_y` = ?');
    params.push(patch.position_y);
  }
  if (sets.length === 0) return;
  params.push(id);
  await pool.query(
    `UPDATE \`DEVICE\` SET ${sets.join(', ')} WHERE \`id_device\` = ?`,
    params,
  );
}

export async function deleteDevice(id: number): Promise<void> {
  await pool.query('DELETE FROM `DEVICE` WHERE `id_device` = ?', [id]);
}
