import { RowDataPacket } from 'mysql2';
import { pool } from '../pool.js';

export interface RoomRow {
  id_room: number;
  name: string;
}

export async function listRooms(): Promise<RoomRow[]> {
  const [rows] = await pool.query<(RoomRow & RowDataPacket)[]>(
    'SELECT `id_room`, `name` FROM `ROOM` ORDER BY `id_room` ASC',
  );
  return rows;
}

export async function findRoomById(id: number): Promise<RoomRow | null> {
  const [rows] = await pool.query<(RoomRow & RowDataPacket)[]>(
    'SELECT `id_room`, `name` FROM `ROOM` WHERE `id_room` = ? LIMIT 1',
    [id],
  );
  return rows[0] ?? null;
}
