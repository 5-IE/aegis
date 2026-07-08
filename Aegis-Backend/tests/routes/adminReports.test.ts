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

vi.mock('../../src/services/reportsService.js', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../../src/services/reportsService.js')>();
  return {
    ...actual,
    getAttendanceReport: vi.fn(),
  };
});

const emptyReport = {
  range: { from: '2026-06-01', to: '2026-06-30', days_with_sessions: 0 },
  summary: { learners: 0, attendance_rate: 0, total_late: 0, total_absent: 0 },
  per_learner: [],
  records: [],
};

const buildTestApp = async () => {
  const { errorHandler } = await import('../../src/middleware/errorHandler.js');
  const { adminReportsRouter } = await import('../../src/routes/admin/reports.js');
  const { signAccessToken } = await import('../../src/services/tokenService.js');
  const app = express();
  app.use(express.json());
  app.use('/api/v1/admin/reports', adminReportsRouter);
  app.use(errorHandler);
  const token = signAccessToken({ sub: 1, role: 'admin' });
  return { app, token };
};

beforeEach(() => vi.clearAllMocks());

describe('GET /admin/reports/attendance', () => {
  it('returns the JSON report', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/reportsService.js');
    const report = {
      range: { from: '2026-06-01', to: '2026-06-30', days_with_sessions: 20 },
      summary: { learners: 2, attendance_rate: 0.9, total_late: 3, total_absent: 4 },
      per_learner: [
        { user_id: 1, name: 'Ada Lovelace', session: 'AM', present: 18, late: 2, absent: 2, attendance_rate: 0.9 },
      ],
      records: [
        { date: '2026-06-01', user_id: 1, name: 'Ada Lovelace', session: 'AM', status: 'early', clocked_in_at: '2026-06-01T01:00:00.000Z', clocked_out_at: '2026-06-01T05:00:00.000Z' },
      ],
    };
    (svc.getAttendanceReport as any).mockResolvedValue(report);
    const res = await request(app)
      .get('/api/v1/admin/reports/attendance?from=2026-06-01&to=2026-06-30')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body).toEqual(report);
    expect(svc.getAttendanceReport).toHaveBeenCalledWith({
      from: '2026-06-01',
      to: '2026-06-30',
      session: undefined,
      userId: undefined,
    });
  });

  it('passes session and user_id filters through', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/reportsService.js');
    (svc.getAttendanceReport as any).mockResolvedValue(emptyReport);
    const res = await request(app)
      .get('/api/v1/admin/reports/attendance?from=2026-06-01&to=2026-06-30&session=PM&user_id=7')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(svc.getAttendanceReport).toHaveBeenCalledWith({
      from: '2026-06-01',
      to: '2026-06-30',
      session: 'PM',
      userId: 7,
    });
  });

  it('rejects missing from', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .get('/api/v1/admin/reports/attendance?to=2026-06-30')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });

  it('rejects bad date format', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .get('/api/v1/admin/reports/attendance?from=2026-6-1&to=2026-06-30')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });

  it('rejects from > to', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .get('/api/v1/admin/reports/attendance?from=2026-07-01&to=2026-06-30')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });

  it('rejects ranges longer than 92 days', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .get('/api/v1/admin/reports/attendance?from=2026-01-01&to=2026-04-03')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });

  it('accepts a range of exactly 92 days', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/reportsService.js');
    (svc.getAttendanceReport as any).mockResolvedValue(emptyReport);
    const res = await request(app)
      .get('/api/v1/admin/reports/attendance?from=2026-01-01&to=2026-04-02')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
  });

  it('rejects unknown query params (strict)', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .get('/api/v1/admin/reports/attendance?from=2026-06-01&to=2026-06-30&extra=1')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });

  it('rejects invalid session and format values', async () => {
    const { app, token } = await buildTestApp();
    const res1 = await request(app)
      .get('/api/v1/admin/reports/attendance?from=2026-06-01&to=2026-06-30&session=EVE')
      .set('Authorization', `Bearer ${token}`);
    expect(res1.status).toBe(400);
    const res2 = await request(app)
      .get('/api/v1/admin/reports/attendance?from=2026-06-01&to=2026-06-30&format=xlsx')
      .set('Authorization', `Bearer ${token}`);
    expect(res2.status).toBe(400);
  });

  it('requires an admin token', async () => {
    const { app } = await buildTestApp();
    const { signAccessToken } = await import('../../src/services/tokenService.js');
    const learnerToken = signAccessToken({ sub: 2, role: 'learner' });
    const res = await request(app)
      .get('/api/v1/admin/reports/attendance?from=2026-06-01&to=2026-06-30')
      .set('Authorization', `Bearer ${learnerToken}`);
    expect(res.status).toBe(403);
  });

  it('streams csv with attachment headers and RFC-4180 quoting', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/reportsService.js');
    (svc.getAttendanceReport as any).mockResolvedValue({
      ...emptyReport,
      records: [
        { date: '2026-06-01', user_id: 1, name: 'Lovelace, Ada "The First"', session: 'AM', status: 'early', clocked_in_at: '2026-06-01T01:00:00.000Z', clocked_out_at: null },
      ],
    });
    const res = await request(app)
      .get('/api/v1/admin/reports/attendance?from=2026-06-01&to=2026-06-30&format=csv')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/^text\/csv/);
    expect(res.headers['content-disposition']).toBe(
      'attachment; filename=aegis-attendance-2026-06-01-2026-06-30.csv',
    );
    const lines = res.text.split('\r\n');
    expect(lines[0]).toBe('date,user_id,name,session,status,clocked_in_at,clocked_out_at');
    expect(lines[1]).toBe(
      '2026-06-01,1,"Lovelace, Ada ""The First""",AM,early,2026-06-01T01:00:00.000Z,',
    );
  });
});
