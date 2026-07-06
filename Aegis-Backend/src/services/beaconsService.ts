import { AppError } from '../lib/errors.js';
import { findRoomById } from '../db/queries/roomQueries.js';
import {
  DeviceWithRoom,
  listDevices,
  findDeviceById,
  findDeviceByIdentifier,
  insertDevice,
  updateDevice,
  deleteDevice,
} from '../db/queries/deviceQueries.js';

export interface BeaconResource {
  id: number;
  name: string;
  beacon_identifier: string;
  room_id: number | null;
  room_name: string | null;
}

export function toBeaconResource(row: DeviceWithRoom): BeaconResource {
  return {
    id: row.id_device,
    name: row.name,
    beacon_identifier: row.identifier,
    room_id: row.id_room,
    room_name: row.room_name,
  };
}

export async function listBeaconsService(
  filter: { assigned?: boolean; roomId?: number },
  page: number,
  perPage: number,
): Promise<{ list: BeaconResource[]; total: number; page: number; per_page: number }> {
  const { list, total } = await listDevices(filter, page, perPage);
  return {
    list: list.map(toBeaconResource),
    total,
    page,
    per_page: perPage,
  };
}

export async function getBeaconService(id: number): Promise<BeaconResource> {
  const row = await findDeviceById(id);
  if (!row) throw new AppError('not_found', 'Device not found');
  return toBeaconResource(row);
}

export async function createBeaconService(input: {
  name: string;
  beacon_identifier: string;
  room_id: number | null;
}): Promise<BeaconResource> {
  if (input.room_id !== null) {
    const room = await findRoomById(input.room_id);
    if (!room) throw new AppError('invalid_request', 'Unknown room_id');
  }
  const dup = await findDeviceByIdentifier(input.beacon_identifier);
  if (dup) throw new AppError('conflict', 'beacon_identifier already exists');

  const id = await insertDevice({
    name: input.name,
    identifier: input.beacon_identifier,
    id_room: input.room_id,
  });
  const row = await findDeviceById(id);
  if (!row) throw new AppError('internal_error', 'Device created but could not be read back');
  return toBeaconResource(row);
}

export async function updateBeaconService(
  id: number,
  patch: { name?: string; beacon_identifier?: string; room_id?: number | null },
): Promise<BeaconResource> {
  if (Object.keys(patch).length === 0) {
    throw new AppError('invalid_request', 'Empty patch');
  }
  const existing = await findDeviceById(id);
  if (!existing) throw new AppError('not_found', 'Device not found');

  if (patch.room_id !== undefined && patch.room_id !== null) {
    const room = await findRoomById(patch.room_id);
    if (!room) throw new AppError('invalid_request', 'Unknown room_id');
  }

  if (patch.beacon_identifier !== undefined && patch.beacon_identifier !== existing.identifier) {
    const collide = await findDeviceByIdentifier(patch.beacon_identifier);
    if (collide && collide.id_device !== id) {
      throw new AppError('conflict', 'beacon_identifier already exists');
    }
  }

  // Translate the API-shaped patch to the DB-shaped patch.
  const dbPatch: { name?: string; identifier?: string; id_room?: number | null } = {};
  if (patch.name !== undefined) dbPatch.name = patch.name;
  if (patch.beacon_identifier !== undefined) dbPatch.identifier = patch.beacon_identifier;
  if (patch.room_id !== undefined) dbPatch.id_room = patch.room_id;

  await updateDevice(id, dbPatch);
  const fresh = await findDeviceById(id);
  if (!fresh) throw new AppError('internal_error', 'Device updated but could not be read back');
  return toBeaconResource(fresh);
}

export async function deleteBeaconService(id: number): Promise<void> {
  const existing = await findDeviceById(id);
  if (!existing) throw new AppError('not_found', 'Device not found');
  await deleteDevice(id);
}
