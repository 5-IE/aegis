import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';
import request from 'supertest';
import express from 'express';

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
vi.mock('../../src/db/queries/attendanceHistoryQueries.js', () => ({
  countByStatus: vi.fn(),
  findByUserAndDate: vi.fn(),
  upsertAttendanceHistory: vi.fn(),
  listHistoriesByUser: vi.fn(),
}));
vi.mock('../../src/db/queries/deviceQueries.js', () => ({
  listAssignedDevices: vi.fn(),
}));
vi.mock('../../src/services/dashboardService.js', () => ({
  getLearnerDashboard: vi.fn(),
  getAbsenceSummary: vi.fn(),
}));
vi.mock('../../src/db/queries/presenceQueries.js', () => ({
  insertPresenceLog: vi.fn(),
  firstPingForUserInWindow: vi.fn().mockResolvedValue(null),
  lastPingForUserInWindow: vi.fn().mockResolvedValue(null),
  firstAndLastPingBulk: vi.fn(),
  currentRoomPerUser: vi.fn(),
}));
vi.mock('../../src/services/configService.js', () => ({
  getSessionConfigs: vi.fn(),
  getSystemConfig: vi.fn().mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' }),
}));

const buildTestApp = async () => {
  const { errorHandler } = await import('../../src/middleware/errorHandler.js');
  const { meRouter } = await import('../../src/routes/me.js');
  const { dashboardRouter } = await import('../../src/routes/dashboard.js');
  const { historiesRouter } = await import('../../src/routes/histories.js');
  const { beaconsRouter } = await import('../../src/routes/beacons.js');
  const { signAccessToken } = await import('../../src/services/tokenService.js');
  const app = express();
  app.use(express.json());
  app.use('/api/v1/me', meRouter);
  app.use('/api/v1/dashboard', dashboardRouter);
  app.use('/api/v1/histories', historiesRouter);
  app.use('/api/v1/beacons', beaconsRouter);
  app.use(errorHandler);
  const token = signAccessToken({ sub: 42, role: 'learner', session: 'AM' });
  return { app, token };
};

beforeEach(() => vi.clearAllMocks());

describe('GET /me', () => {
  it('returns user profile', async () => {
    const { app, token } = await buildTestApp();
    const uq = await import('../../src/db/queries/userQueries.js');
    (uq.findUserById as any).mockResolvedValue({
      id_user: 42, username: 'alice', password: '', email: 'a@x', role: 'learner',
      first_name: 'Alice', last_name: 'Doe', session: 'AM',
    });
    const res = await request(app).get('/api/v1/me').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      id: 42, first_name: 'Alice', last_name: 'Doe', username: 'alice',
      email: 'a@x', role: 'learner', session: 'AM',
    });
  });

  it('rejects without auth', async () => {
    const { app } = await buildTestApp();
    const res = await request(app).get('/api/v1/me');
    expect(res.status).toBe(401);
  });
});

describe('GET /dashboard', () => {
  it('proxies to dashboardService', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/dashboardService.js');
    (svc.getLearnerDashboard as any).mockResolvedValue({
      total_attendance: 92, total_late: 7, leave_taken: 3, today_status: 'Checked In',
    });
    const res = await request(app).get('/api/v1/dashboard').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.today_status).toBe('Checked In');
  });
});

describe('GET /histories', () => {
  it('returns paged history', async () => {
    const { app, token } = await buildTestApp();
    const ah = await import('../../src/db/queries/attendanceHistoryQueries.js');
    (ah.listHistoriesByUser as any).mockResolvedValue({
      list: [{ id_user: 42, date: '2026-07-01', status: 'early' }],
      total: 1,
    });
    // presence queries return null so times are null
    const pq = await import('../../src/db/queries/presenceQueries.js').catch(() => null);
    if (pq) {
      // mock defensively (may not be loaded on this route)
    }
    const res = await request(app).get('/api/v1/histories?page=1&per_page=20').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.list[0].date).toBe('2026-07-01');
  });

  it('rejects month without year', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app).get('/api/v1/histories?month=7').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });
});

describe('GET /beacons', () => {
  it('returns assigned devices only', async () => {
    const { app, token } = await buildTestApp();
    const dq = await import('../../src/db/queries/deviceQueries.js');
    (dq.listAssignedDevices as any).mockResolvedValue([
      { id_device: 1, identifier: '1:2', id_room: 3, room_name: 'Lab' },
    ]);
    const res = await request(app).get('/api/v1/beacons').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.list).toEqual([
      { beacon_identifier: '1:2', room_id: 3, room_name: 'Lab' },
    ]);
  });
});
