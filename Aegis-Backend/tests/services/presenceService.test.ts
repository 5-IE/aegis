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
}));
vi.mock('../../src/db/queries/presenceQueries.js', () => ({
  insertPresenceLog: vi.fn(),
  firstPingForUserInWindow: vi.fn(),
  lastPingForUserInWindow: vi.fn(),
  firstAndLastPingBulk: vi.fn(),
  currentRoomPerUser: vi.fn(),
}));

const load = async () => {
  const svc = await import('../../src/services/presenceService.js');
  const rq = await import('../../src/db/queries/roomQueries.js');
  const pq = await import('../../src/db/queries/presenceQueries.js');
  return { svc, rq, pq };
};

beforeEach(() => vi.clearAllMocks());

describe('recordPresence', () => {
  it('inserts log when room exists', async () => {
    const { svc, rq, pq } = await load();
    (rq.findRoomById as any).mockResolvedValue({ id_room: 3, name: 'Lab' });
    await svc.recordPresence(42, { room_id: 3, position_x: 1, position_y: 2, battery_level: 88 });
    expect(pq.insertPresenceLog).toHaveBeenCalledWith({
      userId: 42, roomId: 3, positionX: 1, positionY: 2, batteryLevel: 88, timestamp: null,
    });
  });

  it('rejects when room missing', async () => {
    const { svc, rq } = await load();
    (rq.findRoomById as any).mockResolvedValue(null);
    await expect(svc.recordPresence(42, { room_id: 99 })).rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('coerces optional fields to null', async () => {
    const { svc, rq, pq } = await load();
    (rq.findRoomById as any).mockResolvedValue({ id_room: 3, name: 'Lab' });
    await svc.recordPresence(42, { room_id: 3 });
    expect(pq.insertPresenceLog).toHaveBeenCalledWith({
      userId: 42, roomId: 3, positionX: null, positionY: null, batteryLevel: null, timestamp: null,
    });
  });
});
