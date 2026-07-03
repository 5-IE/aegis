import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

vi.mock('../../src/db/queries/roomQueries.js', () => ({ listRooms: vi.fn(), findRoomById: vi.fn() }));
vi.mock('../../src/db/queries/presenceQueries.js', () => ({
  insertPresenceLog: vi.fn(),
  firstPingForUserInWindow: vi.fn(),
  lastPingForUserInWindow: vi.fn(),
  firstAndLastPingBulk: vi.fn(),
  currentRoomPerUser: vi.fn(),
}));
vi.mock('../../src/db/queries/userQueries.js', () => ({
  findUserById: vi.fn(),
  findUserByUsername: vi.fn(),
  insertUser: vi.fn(),
  listLearners: vi.fn(),
  listLearnerIds: vi.fn(),
  countLearners: vi.fn(),
}));
vi.mock('../../src/db/queries/attendanceHistoryQueries.js', () => ({
  countByStatus: vi.fn(),
  findByUserAndDate: vi.fn(),
  upsertAttendanceHistory: vi.fn(),
  listHistoriesByUser: vi.fn(),
}));
vi.mock('../../src/services/configService.js', () => ({
  getSessionConfigs: vi.fn(),
  getSystemConfig: vi.fn(),
}));

const load = async () => {
  const svc = await import('../../src/services/roomsService.js');
  const rq = await import('../../src/db/queries/roomQueries.js');
  const pq = await import('../../src/db/queries/presenceQueries.js');
  const uq = await import('../../src/db/queries/userQueries.js');
  const cfg = await import('../../src/services/configService.js');
  return { svc, rq, pq, uq, cfg };
};

const AM = { session: 'AM' as const, start_time: '08:00:00', late_after: '08:15:00', end_time: '12:00:00' };
const PM = { session: 'PM' as const, start_time: '13:00:00', late_after: '13:15:00', end_time: '17:00:00' };

beforeEach(() => vi.clearAllMocks());

describe('listAllRooms', () => {
  it('maps DB rows to id/name', async () => {
    const { svc, rq } = await load();
    (rq.listRooms as any).mockResolvedValue([{ id_room: 1, name: 'Lab A' }, { id_room: 2, name: 'Lab B' }]);
    const r = await svc.listAllRooms();
    expect(r).toEqual([{ id: 1, name: 'Lab A' }, { id: 2, name: 'Lab B' }]);
  });
});

describe('getRoomMap', () => {
  it('throws not_found when room missing', async () => {
    const { svc, rq } = await load();
    (rq.findRoomById as any).mockResolvedValue(null);
    await expect(svc.getRoomMap(99, new Date('2026-07-03T02:00:00Z'))).rejects.toMatchObject({ code: 'not_found' });
  });

  it('returns only users whose current room is this room', async () => {
    const { svc, rq, pq, uq, cfg } = await load();
    (rq.findRoomById as any).mockResolvedValue({ id_room: 1, name: 'Lab A' });
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' });
    (pq.currentRoomPerUser as any).mockResolvedValue([
      { id_user: 42, id_room: 1, last_seen: new Date(), position_x: 1, position_y: 2, log_id: 100 },
      { id_user: 43, id_room: 2, last_seen: new Date(), position_x: 3, position_y: 4, log_id: 101 },
    ]);
    (uq.findUserById as any).mockImplementation(async (id: number) => ({
      id_user: id, username: `u${id}`, password: '', email: '', role: 'learner', first_name: `U${id}`, last_name: null, session: 'AM',
    }));

    const r = await svc.getRoomMap(1, new Date('2026-07-03T02:00:00Z'));
    expect(r.list).toHaveLength(1);
    expect(r.list[0].user.id).toBe(42);
    expect(r.list[0].x).toBe(1);
  });
});

describe('getRoomCurrentOccupants', () => {
  it('computes duration and status', async () => {
    const { svc, rq, pq, uq, cfg } = await load();
    (rq.findRoomById as any).mockResolvedValue({ id_room: 1, name: 'Lab A' });
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' });
    (cfg.getSessionConfigs as any).mockResolvedValue({ AM, PM });
    const now = new Date('2026-07-03T02:00:00Z');
    (pq.currentRoomPerUser as any).mockResolvedValue([
      { id_user: 42, id_room: 1, last_seen: new Date('2026-07-03T01:55:00Z'), position_x: null, position_y: null, log_id: 100 },
    ]);
    (pq.firstPingForUserInWindow as any).mockResolvedValue(new Date('2026-07-03T01:00:00Z'));
    (uq.findUserById as any).mockResolvedValue({ id_user: 42, username: 'a', password: '', email: '', role: 'learner', first_name: 'A', last_name: 'Z', session: 'AM' });

    const r = await svc.getRoomCurrentOccupants(1, now);
    expect(r.list).toHaveLength(1);
    expect(r.list[0].duration_seconds).toBe(60 * 60);
    expect(r.list[0].status).toBe('Checked In');
  });
});

describe('getRoomAdditionalData', () => {
  it('returns fixed temp/humidity and live people count', async () => {
    const { svc, rq, pq, cfg } = await load();
    (rq.findRoomById as any).mockResolvedValue({ id_room: 1, name: 'Lab A' });
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' });
    (pq.currentRoomPerUser as any).mockResolvedValue([
      { id_user: 42, id_room: 1, last_seen: new Date(), position_x: null, position_y: null, log_id: 1 },
      { id_user: 43, id_room: 1, last_seen: new Date(), position_x: null, position_y: null, log_id: 2 },
      { id_user: 44, id_room: 2, last_seen: new Date(), position_x: null, position_y: null, log_id: 3 },
    ]);

    const r = await svc.getRoomAdditionalData(1, new Date('2026-07-03T02:00:00Z'));
    expect(r.room_temperature).toBe(24.5);
    expect(r.humidity).toBe(62);
    expect(r.people_in_room).toBe(2);
  });
});
