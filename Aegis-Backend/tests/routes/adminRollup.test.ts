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

vi.mock('../../src/services/rollupService.js', () => ({
  runRollup: vi.fn(),
}));

const buildTestApp = async () => {
  const { errorHandler } = await import('../../src/middleware/errorHandler.js');
  const { rollupRouter } = await import('../../src/routes/admin/rollup.js');
  const { signAccessToken } = await import('../../src/services/tokenService.js');
  const app = express();
  app.use(express.json());
  app.use('/api/v1/admin/rollup', rollupRouter);
  app.use(errorHandler);
  const token = signAccessToken({ sub: 1, role: 'admin' });
  return { app, token };
};

beforeEach(() => vi.clearAllMocks());

describe('POST /admin/rollup', () => {
  it('returns processed and skipped_leave', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/rollupService.js');
    (svc.runRollup as any).mockResolvedValue({ processed: 60, skipped_leave: 2 });
    const res = await request(app).post('/api/v1/admin/rollup').set('Authorization', `Bearer ${token}`).send({});
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ processed: 60, skipped_leave: 2 });
  });

  it('rejects invalid date format', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app).post('/api/v1/admin/rollup').set('Authorization', `Bearer ${token}`).send({ date: 'bad' });
    expect(res.status).toBe(400);
  });

  it('passes user_id through', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/rollupService.js');
    (svc.runRollup as any).mockResolvedValue({ processed: 1, skipped_leave: 0 });
    const res = await request(app).post('/api/v1/admin/rollup').set('Authorization', `Bearer ${token}`).send({ user_id: 5 });
    expect(res.status).toBe(200);
    expect(svc.runRollup).toHaveBeenCalledWith({ userId: 5 });
  });
});
