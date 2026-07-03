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
  const svc = await import('../../src/services/dashboardService.js');
  const ah = await import('../../src/db/queries/attendanceHistoryQueries.js');
  const pq = await import('../../src/db/queries/presenceQueries.js');
  const uq = await import('../../src/db/queries/userQueries.js');
  const cfg = await import('../../src/services/configService.js');
  return { svc, ah, pq, uq, cfg };
};

const AM = { session: 'AM' as const, start_time: '08:00:00', late_after: '08:15:00', end_time: '12:00:00' };
const PM = { session: 'PM' as const, start_time: '13:00:00', late_after: '13:15:00', end_time: '17:00:00' };

beforeEach(() => vi.clearAllMocks());

describe('getLearnerDashboard', () => {
  it('rolls up counters and computes today_status', async () => {
    const { svc, ah, pq, uq, cfg } = await load();
    (uq.findUserById as any).mockResolvedValue({ id_user: 42, session: 'AM', role: 'learner', username: 'a', first_name: 'A', last_name: 'B', email: 'a@x', password: '' });
    (ah.countByStatus as any).mockResolvedValue({ early: 80, late: 12, leave: 3 });
    (ah.findByUserAndDate as any).mockResolvedValue(null);
    (pq.firstPingForUserInWindow as any).mockResolvedValue(new Date('2026-07-03T01:10:00Z'));
    (pq.lastPingForUserInWindow as any).mockResolvedValue(new Date('2026-07-03T01:10:00Z'));
    (cfg.getSessionConfigs as any).mockResolvedValue({ AM, PM });
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' });

    const r = await svc.getLearnerDashboard(42, new Date('2026-07-03T02:00:00Z'));
    expect(r.total_attendance).toBe(92);
    expect(r.total_late).toBe(12);
    expect(r.leave_taken).toBe(3);
    expect(r.today_status).toBe('Checked In');
  });

  it('throws not_found when user missing', async () => {
    const { svc, uq } = await load();
    (uq.findUserById as any).mockResolvedValue(null);
    await expect(svc.getLearnerDashboard(999, new Date())).rejects.toMatchObject({ code: 'not_found' });
  });
});

describe('getAbsenceSummary', () => {
  it('buckets learners by first-ping vs session windows', async () => {
    const { svc, pq, uq, cfg } = await load();
    (cfg.getSessionConfigs as any).mockResolvedValue({ AM, PM });
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' });
    (uq.listLearnerIds as any).mockResolvedValue([1, 2, 3, 4]);
    // now = 09:00 local (AM window still open)
    const now = new Date('2026-07-03T02:00:00Z');
    // 1: on_time (first ping 08:05 local); 2: late_clock_in (08:20 local); 3: no ping, still in window; 4: no ping
    (pq.firstAndLastPingBulk as any).mockResolvedValue(new Map([
      [1, { first: new Date('2026-07-03T01:05:00Z'), last: new Date('2026-07-03T01:05:00Z') }],
      [2, { first: new Date('2026-07-03T01:20:00Z'), last: new Date('2026-07-03T01:20:00Z') }],
    ]));
    (uq.findUserById as any).mockImplementation(async (id: number) => ({ id_user: id, session: 'AM', role: 'learner', username: 'x', first_name: 'x', last_name: 'y', email: 'a@x', password: '' }));

    const r = await svc.getAbsenceSummary(now);
    expect(r.present_summary.on_time).toBe(1);
    expect(r.present_summary.late_clock_in).toBe(1);
    expect(r.absent_summary.no_clock_in).toBe(2);
    expect(r.absent_summary.absent).toBe(0);
  });

  it('counts leave rows as absent', async () => {
    const { svc, ah, pq, uq, cfg } = await load();
    (cfg.getSessionConfigs as any).mockResolvedValue({ AM, PM });
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' });
    (uq.listLearnerIds as any).mockResolvedValue([1]);
    (pq.firstAndLastPingBulk as any).mockResolvedValue(new Map());
    (uq.findUserById as any).mockResolvedValue({ id_user: 1, session: 'AM', role: 'learner', username: 'x', first_name: 'x', last_name: 'y', email: 'a@x', password: '' });
    (ah.findByUserAndDate as any).mockResolvedValue({ id_user: 1, date: '2026-07-03', status: 'leave' });

    const now = new Date('2026-07-03T02:00:00Z');
    const r = await svc.getAbsenceSummary(now);
    expect(r.absent_summary.absent).toBe(1);
    expect(r.absent_summary.no_clock_in).toBe(0);
  });
});
