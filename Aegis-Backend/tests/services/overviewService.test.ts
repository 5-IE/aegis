import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

vi.mock('../../src/db/queries/userQueries.js', () => ({
  findUserById: vi.fn(),
  findUserByUsername: vi.fn(),
  insertUser: vi.fn(),
  listLearners: vi.fn(),
  listLearnerIds: vi.fn(),
  countLearners: vi.fn(),
}));
vi.mock('../../src/db/queries/presenceQueries.js', () => ({
  insertPresenceLog: vi.fn(),
  firstPingForUserInWindow: vi.fn(),
  lastPingForUserInWindow: vi.fn(),
  firstAndLastPingBulk: vi.fn(),
  currentRoomPerUser: vi.fn(),
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
  const svc = await import('../../src/services/overviewService.js');
  const uq = await import('../../src/db/queries/userQueries.js');
  const pq = await import('../../src/db/queries/presenceQueries.js');
  const cfg = await import('../../src/services/configService.js');
  return { svc, uq, pq, cfg };
};

const AM = { session: 'AM' as const, start_time: '08:00:00', late_after: '08:15:00', end_time: '12:00:00' };
const PM = { session: 'PM' as const, start_time: '13:00:00', late_after: '13:15:00', end_time: '17:00:00' };

beforeEach(() => vi.clearAllMocks());

describe('getOverview', () => {
  it('returns paged list with clocked times and today_status', async () => {
    const { svc, uq, pq, cfg } = await load();
    (cfg.getSessionConfigs as any).mockResolvedValue({ AM, PM });
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' });
    (uq.listLearners as any).mockResolvedValue({
      list: [
        { id_user: 1, username: 'alice', password: '', email: 'a@x', role: 'learner', first_name: 'Alice', last_name: 'Doe', session: 'AM' },
        { id_user: 2, username: 'bob', password: '', email: 'b@x', role: 'learner', first_name: null, last_name: null, session: 'PM' },
      ],
      total: 2,
    });
    (pq.firstAndLastPingBulk as any).mockResolvedValue(new Map([
      [1, { first: new Date('2026-07-03T01:10:00Z'), last: new Date('2026-07-03T01:10:00Z') }],
    ]));

    const now = new Date('2026-07-03T02:00:00Z');
    const r = await svc.getOverview(now, {}, 1, 20);
    expect(r.list).toHaveLength(2);
    expect(r.list[0].name).toBe('Alice Doe');
    expect(r.list[0].clocked_in_at).toBe('2026-07-03T01:10:00.000Z');
    expect(r.list[0].status).toBe('Checked In');
    expect(r.list[1].name).toBe('bob');
    expect(r.list[1].clocked_in_at).toBeNull();
    expect(r.total).toBe(2);
  });
});
