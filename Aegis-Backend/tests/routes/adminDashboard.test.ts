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

vi.mock('../../src/services/dashboardService.js', () => ({
  getLearnerDashboard: vi.fn(),
  getAbsenceSummary: vi.fn(),
}));
vi.mock('../../src/services/overviewService.js', () => ({
  getOverview: vi.fn(),
}));

const buildTestApp = async (role: 'admin' | 'learner' = 'admin') => {
  const { errorHandler } = await import('../../src/middleware/errorHandler.js');
  const { absenceSummaryRouter } = await import('../../src/routes/admin/absenceSummary.js');
  const { adminOverviewRouter } = await import('../../src/routes/admin/overview.js');
  const { signAccessToken } = await import('../../src/services/tokenService.js');
  const app = express();
  app.use(express.json());
  app.use('/api/v1/admin/absence-summary', absenceSummaryRouter);
  app.use('/api/v1/admin/overview', adminOverviewRouter);
  app.use(errorHandler);
  const token = signAccessToken({ sub: 1, role });
  return { app, token };
};

beforeEach(() => vi.clearAllMocks());

describe('GET /admin/absence-summary', () => {
  it('returns counts', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/dashboardService.js');
    (svc.getAbsenceSummary as any).mockResolvedValue({
      present_summary: { on_time: 54, late_clock_in: 6 },
      absent_summary: { absent: 3, no_clock_in: 2 },
    });
    const res = await request(app).get('/api/v1/admin/absence-summary').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.present_summary.on_time).toBe(54);
  });

  it('rejects learner', async () => {
    const { app, token } = await buildTestApp('learner');
    const res = await request(app).get('/api/v1/admin/absence-summary').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(403);
  });
});

describe('GET /admin/overview', () => {
  it('proxies query params', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/overviewService.js');
    (svc.getOverview as any).mockResolvedValue({ list: [], page: 1, per_page: 20, total: 0 });
    const res = await request(app).get('/api/v1/admin/overview?name=Ali&session=AM').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(svc.getOverview).toHaveBeenCalledWith(expect.any(Date), { name: 'Ali', session: 'AM' }, 1, 20);
  });

  it('rejects invalid session', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app).get('/api/v1/admin/overview?session=XX').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });
});
