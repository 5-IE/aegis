import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

vi.mock('../../src/db/queries/roomQueries.js', () => ({
  listRooms: vi.fn(),
  findRoomById: vi.fn(),
  insertRoom: vi.fn(),
  updateRoomName: vi.fn(),
  deleteRoom: vi.fn(),
}));

vi.mock('../../src/db/queries/deviceQueries.js', () => ({
  listAssignedDevices: vi.fn(),
  listDevices: vi.fn(),
  findDeviceById: vi.fn(),
  findDeviceByIdentifier: vi.fn(),
  insertDevice: vi.fn(),
  updateDevice: vi.fn(),
  deleteDevice: vi.fn(),
}));

const load = async () => {
  const svc = await import('../../src/services/beaconsService.js');
  const rq = await import('../../src/db/queries/roomQueries.js');
  const dq = await import('../../src/db/queries/deviceQueries.js');
  return { svc, rq, dq };
};

const deviceRow = {
  id_device: 1,
  name: 'iBeacon 1',
  identifier: '1:1000',
  id_room: 3,
  room_name: 'Lab 3.02',
};

const unassignedRow = {
  id_device: 2,
  name: 'iBeacon Spare',
  identifier: '1:9999',
  id_room: null,
  room_name: null,
};

beforeEach(() => vi.clearAllMocks());

describe('toBeaconResource', () => {
  it('maps id_device to id', async () => {
    const { svc } = await load();
    const r = svc.toBeaconResource(deviceRow);
    expect(r).toEqual({
      id: 1,
      name: 'iBeacon 1',
      beacon_identifier: '1:1000',
      room_id: 3,
      room_name: 'Lab 3.02',
    });
  });

  it('preserves null room fields for unassigned', async () => {
    const { svc } = await load();
    const r = svc.toBeaconResource(unassignedRow);
    expect(r.room_id).toBeNull();
    expect(r.room_name).toBeNull();
  });
});

describe('listBeaconsService', () => {
  it('returns paged list', async () => {
    const { svc, dq } = await load();
    (dq.listDevices as any).mockResolvedValue({ list: [deviceRow, unassignedRow], total: 2 });
    const r = await svc.listBeaconsService({}, 1, 20);
    expect(r.total).toBe(2);
    expect(r.list).toHaveLength(2);
    expect(r.page).toBe(1);
    expect(r.per_page).toBe(20);
  });
});

describe('getBeaconService', () => {
  it('returns resource for existing device', async () => {
    const { svc, dq } = await load();
    (dq.findDeviceById as any).mockResolvedValue(deviceRow);
    const r = await svc.getBeaconService(1);
    expect(r.id).toBe(1);
  });

  it('throws not_found when device missing', async () => {
    const { svc, dq } = await load();
    (dq.findDeviceById as any).mockResolvedValue(null);
    await expect(svc.getBeaconService(999)).rejects.toMatchObject({ code: 'not_found' });
  });
});

describe('createBeaconService', () => {
  it('creates an assigned beacon', async () => {
    const { svc, rq, dq } = await load();
    (rq.findRoomById as any).mockResolvedValue({ id_room: 3, name: 'Lab 3.02' });
    (dq.findDeviceByIdentifier as any).mockResolvedValue(null);
    (dq.insertDevice as any).mockResolvedValue(1);
    (dq.findDeviceById as any).mockResolvedValue(deviceRow);
    const r = await svc.createBeaconService({
      name: 'iBeacon 1',
      beacon_identifier: '1:1000',
      room_id: 3,
    });
    expect(r.id).toBe(1);
    expect(dq.insertDevice).toHaveBeenCalledWith({
      name: 'iBeacon 1',
      identifier: '1:1000',
      id_room: 3,
    });
  });

  it('creates an unassigned beacon (room_id null)', async () => {
    const { svc, dq } = await load();
    (dq.findDeviceByIdentifier as any).mockResolvedValue(null);
    (dq.insertDevice as any).mockResolvedValue(2);
    (dq.findDeviceById as any).mockResolvedValue(unassignedRow);
    const r = await svc.createBeaconService({
      name: 'iBeacon Spare',
      beacon_identifier: '1:9999',
      room_id: null,
    });
    expect(r.room_id).toBeNull();
    expect(dq.insertDevice).toHaveBeenCalledWith({
      name: 'iBeacon Spare',
      identifier: '1:9999',
      id_room: null,
    });
  });

  it('throws invalid_request when room_id refers to a missing room', async () => {
    const { svc, rq } = await load();
    (rq.findRoomById as any).mockResolvedValue(null);
    await expect(
      svc.createBeaconService({ name: 'x', beacon_identifier: 'y', room_id: 999 }),
    ).rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('throws conflict on duplicate identifier', async () => {
    const { svc, rq, dq } = await load();
    (rq.findRoomById as any).mockResolvedValue({ id_room: 3, name: 'Lab' });
    (dq.findDeviceByIdentifier as any).mockResolvedValue(deviceRow);
    await expect(
      svc.createBeaconService({ name: 'x', beacon_identifier: '1:1000', room_id: 3 }),
    ).rejects.toMatchObject({ code: 'conflict' });
  });
});

describe('updateBeaconService', () => {
  it('renames a beacon', async () => {
    const { svc, dq } = await load();
    (dq.findDeviceById as any)
      .mockResolvedValueOnce(deviceRow)
      .mockResolvedValueOnce({ ...deviceRow, name: 'iBeacon 1 (repaired)' });
    const r = await svc.updateBeaconService(1, { name: 'iBeacon 1 (repaired)' });
    expect(r.name).toBe('iBeacon 1 (repaired)');
    expect(dq.updateDevice).toHaveBeenCalledWith(1, { name: 'iBeacon 1 (repaired)' });
  });

  it('unassigns a beacon (room_id: null)', async () => {
    const { svc, dq } = await load();
    (dq.findDeviceById as any)
      .mockResolvedValueOnce(deviceRow)
      .mockResolvedValueOnce({ ...deviceRow, id_room: null, room_name: null });
    const r = await svc.updateBeaconService(1, { room_id: null });
    expect(r.room_id).toBeNull();
    expect(dq.updateDevice).toHaveBeenCalledWith(1, { id_room: null });
  });

  it('throws not_found when device missing', async () => {
    const { svc, dq } = await load();
    (dq.findDeviceById as any).mockResolvedValue(null);
    await expect(svc.updateBeaconService(999, { name: 'x' })).rejects.toMatchObject({ code: 'not_found' });
  });

  it('throws invalid_request on empty patch', async () => {
    const { svc } = await load();
    await expect(svc.updateBeaconService(1, {})).rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('throws invalid_request when new room_id refers to missing room', async () => {
    const { svc, dq, rq } = await load();
    (dq.findDeviceById as any).mockResolvedValue(deviceRow);
    (rq.findRoomById as any).mockResolvedValue(null);
    await expect(svc.updateBeaconService(1, { room_id: 999 })).rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('throws conflict when new identifier taken by another device', async () => {
    const { svc, dq } = await load();
    (dq.findDeviceById as any).mockResolvedValue(deviceRow);
    (dq.findDeviceByIdentifier as any).mockResolvedValue({ ...deviceRow, id_device: 99 });
    await expect(svc.updateBeaconService(1, { beacon_identifier: '1:2000' })).rejects.toMatchObject({ code: 'conflict' });
  });

  it('allows identifier update to same value (idempotent)', async () => {
    const { svc, dq } = await load();
    (dq.findDeviceById as any)
      .mockResolvedValueOnce(deviceRow)
      .mockResolvedValueOnce(deviceRow);
    (dq.findDeviceByIdentifier as any).mockResolvedValue(deviceRow);
    const r = await svc.updateBeaconService(1, { beacon_identifier: '1:1000' });
    expect(r.beacon_identifier).toBe('1:1000');
  });
});

describe('deleteBeaconService', () => {
  it('deletes existing device', async () => {
    const { svc, dq } = await load();
    (dq.findDeviceById as any).mockResolvedValue(deviceRow);
    await svc.deleteBeaconService(1);
    expect(dq.deleteDevice).toHaveBeenCalledWith(1);
  });

  it('throws not_found when device missing', async () => {
    const { svc, dq } = await load();
    (dq.findDeviceById as any).mockResolvedValue(null);
    await expect(svc.deleteBeaconService(999)).rejects.toMatchObject({ code: 'not_found' });
  });
});
