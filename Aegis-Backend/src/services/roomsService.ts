import { AppError } from '../lib/errors.js';
import { listRooms, findRoomById, insertRoom, updateRoomName, deleteRoom } from '../db/queries/roomQueries.js';
import { currentRoomPerUser, firstPingForUserInWindow, countPresenceLogsForRoom } from '../db/queries/presenceQueries.js';
import { findUserById, UserRow } from '../db/queries/userQueries.js';
import { findByUserAndDate } from '../db/queries/attendanceHistoryQueries.js';
import { getSystemConfig } from './configService.js';
import { computeTodayStatus, localDayBoundsUtc, localDateStr, TodayStatus } from './statusService.js';

function displayName(row: UserRow): string {
  const parts = [row.first_name, row.last_name].filter((x): x is string => !!x);
  const joined = parts.join(' ').trim();
  return joined || row.username;
}

function userResource(row: UserRow): { id: number; name: string; session: 'AM' | 'PM' | null } {
  return {
    id: row.id_user,
    name: displayName(row),
    session: row.role === 'learner' ? row.session : null,
  };
}

export async function listAllRooms(): Promise<Array<{ id: number; name: string }>> {
  const rows = await listRooms();
  return rows.map((r) => ({ id: r.id_room, name: r.name }));
}

async function ensureRoomExists(roomId: number): Promise<void> {
  const room = await findRoomById(roomId);
  if (!room) throw new AppError('not_found', 'Room not found');
}

async function currentUsersInRoom(roomId: number, now: Date) {
  const sys = await getSystemConfig();
  const { startUtc, endUtc } = localDayBoundsUtc(now, sys.timezone);
  const stalenessSince = new Date(now.getTime() - sys.presence_staleness_minutes * 60_000);
  const rows = await currentRoomPerUser(startUtc, endUtc, stalenessSince);
  return rows.filter((r) => r.id_room === roomId);
}

export async function getRoomMap(
  roomId: number,
  now: Date,
): Promise<{ list: Array<{ id: number; user: { id: number; name: string; session: 'AM' | 'PM' | null }; x: number | null; y: number | null }> }> {
  await ensureRoomExists(roomId);
  const rows = await currentUsersInRoom(roomId, now);
  const users = await Promise.all(rows.map((r) => findUserById(r.id_user)));
  const list = rows.map((r, i) => {
    const u = users[i];
    if (!u) return null;
    return { id: r.log_id, user: userResource(u), x: r.position_x, y: r.position_y };
  }).filter((x): x is NonNullable<typeof x> => x !== null);
  return { list };
}

export async function getRoomCurrentOccupants(
  roomId: number,
  now: Date,
): Promise<{ list: Array<{ user: { id: number; name: string; session: 'AM' | 'PM' | null }; duration_seconds: number; status: TodayStatus }> }> {
  await ensureRoomExists(roomId);
  const sys = await getSystemConfig();
  const { startUtc, endUtc } = localDayBoundsUtc(now, sys.timezone);
  const rows = await currentUsersInRoom(roomId, now);
  const enriched = await Promise.all(rows.map(async (r) => {
    const user = await findUserById(r.id_user);
    if (!user) return null;
    const first = await firstPingForUserInWindow(r.id_user, startUtc, endUtc);
    const leaveRow = await findByUserAndDate(r.id_user, localDateStr(now, sys.timezone));
    const hasLeave = leaveRow?.status === 'leave';
    const status = await computeTodayStatus(user.session, now, first, r.last_seen, hasLeave);
    const duration_seconds = first ? Math.max(0, Math.floor((now.getTime() - first.getTime()) / 1000)) : 0;
    return { user: userResource(user), duration_seconds, status };
  }));
  return { list: enriched.filter((x): x is NonNullable<typeof x> => x !== null) };
}

export async function getRoomAdditionalData(
  roomId: number,
  now: Date,
): Promise<{ room_temperature: number; humidity: number; people_in_room: number }> {
  await ensureRoomExists(roomId);
  const rows = await currentUsersInRoom(roomId, now);
  return { room_temperature: 24.5, humidity: 62, people_in_room: rows.length };
}

export async function createRoomService(input: { name: string }): Promise<{ id: number; name: string }> {
  const id = await insertRoom(input.name);
  const row = await findRoomById(id);
  if (!row) throw new AppError('internal_error', 'Room created but could not be read back');
  return { id: row.id_room, name: row.name };
}

export async function updateRoomService(
  id: number,
  patch: { name?: string },
): Promise<{ id: number; name: string }> {
  if (Object.keys(patch).length === 0) {
    throw new AppError('invalid_request', 'Empty patch');
  }
  const existing = await findRoomById(id);
  if (!existing) throw new AppError('not_found', 'Room not found');
  if (patch.name !== undefined) {
    await updateRoomName(id, patch.name);
  }
  const fresh = await findRoomById(id);
  if (!fresh) throw new AppError('internal_error', 'Room updated but could not be read back');
  return { id: fresh.id_room, name: fresh.name };
}

export async function deleteRoomService(id: number): Promise<void> {
  const existing = await findRoomById(id);
  if (!existing) throw new AppError('not_found', 'Room not found');
  const logCount = await countPresenceLogsForRoom(id);
  if (logCount > 0) {
    throw new AppError('conflict', `Cannot delete room with recorded presence — has ${logCount} log entries`);
  }
  await deleteRoom(id);
}
