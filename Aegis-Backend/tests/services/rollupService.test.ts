import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

vi.mock('../../src/db/queries/attendanceHistoryQueries.js', () => ({
  countByStatus: vi.fn(),
  findByUserAndDate: vi.fn(),
  upsertAttendanceHistory: vi.fn(),
  listHistoriesByUser: vi.fn(),
}));
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
vi.mock('../../src/services/configService.js', () => ({
  getSessionConfigs: vi.fn(),
  getSystemConfig: vi.fn(),
}));

const load = async () => {
  const svc = await import('../../src/services/rollupService.js');
  const ah = await import('../../src/db/queries/attendanceHistoryQueries.js');
  const pq = await import('../../src/db/queries/presenceQueries.js');
  const uq = await import('../../src/db/queries/userQueries.js');
  const cfg = await import('../../src/services/configService.js');
  return { svc, ah, pq, uq, cfg };
};

const AM = { session: 'AM' as const, start_time: '08:00:00', late_after: '08:15:00', end_time: '12:00:00' };
const PM = { session: 'PM' as const, start_time: '13:00:00', late_after: '13:15:00', end_time: '17:00:00' };

beforeEach(() => vi.clearAllMocks());

describe('runRollup', () => {
  it('processes all learners for yesterday when no args', async () => {
    const { svc, ah, pq, uq, cfg } = await load();
    (cfg.getSessionConfigs as any).mockResolvedValue({ AM, PM });
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' });
    (uq.listLearnerIds as any).mockResolvedValue([1, 2, 3]);
    (uq.findUserById as any).mockImplementation(async (id: number) => ({ id_user: id, session: 'AM', role: 'learner', username: 'x', first_name: 'x', last_name: 'y', email: 'a@x', password: '' }));
    (ah.findByUserAndDate as any).mockImplementation(async (id: number) => id === 2 ? { id_user: 2, date: '2026-07-02', status: 'leave' } : null);
    (pq.firstPingForUserInWindow as any).mockImplementation(async (id: number) => id === 1 ? new Date('2026-07-02T01:10:00Z') : null);

    const r = await svc.runRollup({ now: new Date('2026-07-03T02:00:00Z') });
    expect(r.processed).toBe(2);      // user 1 (early) and 3 (absent)
    expect(r.skipped_leave).toBe(1);  // user 2

    expect(ah.upsertAttendanceHistory).toHaveBeenCalledWith(1, '2026-07-02', 'early');
    expect(ah.upsertAttendanceHistory).toHaveBeenCalledWith(3, '2026-07-02', 'absent');
    expect(ah.upsertAttendanceHistory).not.toHaveBeenCalledWith(2, expect.anything(), expect.anything());
  });

  it('processes a single user when userId given', async () => {
    const { svc, ah, pq, uq, cfg } = await load();
    (cfg.getSessionConfigs as any).mockResolvedValue({ AM, PM });
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' });
    (uq.findUserById as any).mockResolvedValue({ id_user: 5, session: 'PM', role: 'learner', username: 'x', first_name: 'x', last_name: 'y', email: 'a@x', password: '' });
    (ah.findByUserAndDate as any).mockResolvedValue(null);
    (pq.firstPingForUserInWindow as any).mockResolvedValue(new Date('2026-07-02T06:20:00Z')); // 13:20 local = after PM late_after

    const r = await svc.runRollup({ userId: 5, date: '2026-07-02' });
    expect(r.processed).toBe(1);
    expect(r.skipped_leave).toBe(0);
    expect(ah.upsertAttendanceHistory).toHaveBeenCalledWith(5, '2026-07-02', 'late');
  });
});
