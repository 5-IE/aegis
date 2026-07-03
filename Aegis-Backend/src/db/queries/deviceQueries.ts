import { RowDataPacket } from 'mysql2';
import { pool } from '../pool.js';

export interface DeviceWithRoom {
  id_device: number;
  identifier: string;
  id_room: number;
  room_name: string;
}

export async function listAssignedDevices(): Promise<DeviceWithRoom[]> {
  const [rows] = await pool.query<(DeviceWithRoom & RowDataPacket)[]>(
    `SELECT d.\`id_device\`, d.\`identifier\`, d.\`id_room\`, r.\`name\` AS room_name
     FROM \`DEVICE\` d
     JOIN \`ROOM\` r ON r.\`id_room\` = d.\`id_room\`
     WHERE d.\`id_room\` IS NOT NULL
     ORDER BY d.\`id_device\` ASC`,
  );
  return rows;
}
