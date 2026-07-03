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

vi.mock('../../src/services/configService.js', () => ({
  getSessionConfigs: vi.fn(),
  updateSessionConfig: vi.fn(),
  getSystemConfig: vi.fn(),
  updateSystemConfig: vi.fn(),
  invalidateConfigCache: vi.fn(),
}));

const buildTestApp = async () => {
  const { errorHandler } = await import('../../src/middleware/errorHandler.js');
  const { sessionConfigRouter } = await import('../../src/routes/admin/sessionConfig.js');
  const { systemConfigRouter } = await import('../../src/routes/admin/systemConfig.js');
  const { signAccessToken } = await import('../../src/services/tokenService.js');
  const app = express();
  app.use(express.json());
  app.use('/api/v1/admin/session-config', sessionConfigRouter);
  app.use('/api/v1/admin/system-config', systemConfigRouter);
  app.use(errorHandler);
  const token = signAccessToken({ sub: 1, role: 'admin' });
  return { app, token };
};

beforeEach(() => vi.clearAllMocks());

describe('session-config', () => {
  it('GET returns AM+PM', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/configService.js');
    (svc.getSessionConfigs as any).mockResolvedValue({
      AM: { session: 'AM', start_time: '08:00:00', late_after: '08:15:00', end_time: '12:00:00' },
      PM: { session: 'PM', start_time: '13:00:00', late_after: '13:15:00', end_time: '17:00:00' },
    });
    const res = await request(app).get('/api/v1/admin/session-config').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.AM.start_time).toBe('08:00:00');
  });

  it('PUT /:session validates body', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app).put('/api/v1/admin/session-config/AM')
      .set('Authorization', `Bearer ${token}`)
      .send({ start_time: '08:00', late_after: '08:15:00', end_time: '12:00:00' });
    expect(res.status).toBe(400);
  });

  it('PUT /:session returns 204', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/configService.js');
    (svc.updateSessionConfig as any).mockResolvedValue(undefined);
    const res = await request(app).put('/api/v1/admin/session-config/AM')
      .set('Authorization', `Bearer ${token}`)
      .send({ start_time: '08:00:00', late_after: '08:15:00', end_time: '12:00:00' });
    expect(res.status).toBe(204);
  });
});

describe('system-config', () => {
  it('GET returns settings', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/configService.js');
    (svc.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' });
    const res = await request(app).get('/api/v1/admin/system-config').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.presence_staleness_minutes).toBe(5);
  });

  it('PUT accepts partial update', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/configService.js');
    (svc.updateSystemConfig as any).mockResolvedValue(undefined);
    const res = await request(app).put('/api/v1/admin/system-config')
      .set('Authorization', `Bearer ${token}`)
      .send({ timezone: 'Asia/Jakarta' });
    expect(res.status).toBe(204);
    expect(svc.updateSystemConfig).toHaveBeenCalledWith({ timezone: 'Asia/Jakarta' });
  });

  it('PUT rejects unknown fields', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app).put('/api/v1/admin/system-config')
      .set('Authorization', `Bearer ${token}`)
      .send({ unknown_key: 'x' });
    expect(res.status).toBe(400);
  });
});
