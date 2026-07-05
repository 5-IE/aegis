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

vi.mock('../../src/services/presenceService.js', () => ({
  recordPresence: vi.fn(),
}));

const buildTestApp = async () => {
  const { errorHandler } = await import('../../src/middleware/errorHandler.js');
  const { presenceRouter } = await import('../../src/routes/presence.js');
  const { signAccessToken } = await import('../../src/services/tokenService.js');
  const app = express();
  app.use(express.json());
  app.use('/api/v1/presence', presenceRouter);
  app.use(errorHandler);
  const token = signAccessToken({ sub: 42, role: 'learner', session: 'AM' });
  return { app, token };
};

beforeEach(() => vi.clearAllMocks());

describe('POST /presence', () => {
  it('returns 204 on valid body', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/presenceService.js');
    (svc.recordPresence as any).mockResolvedValue(undefined);
    const res = await request(app)
      .post('/api/v1/presence')
      .set('Authorization', `Bearer ${token}`)
      .send({ room_id: 3, position_x: 1.5, position_y: 2.5, battery_level: 88 });
    expect(res.status).toBe(204);
    expect(svc.recordPresence).toHaveBeenCalledWith(42, {
      room_id: 3, position_x: 1.5, position_y: 2.5, battery_level: 88,
    });
  });

  it('rejects missing room_id', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .post('/api/v1/presence')
      .set('Authorization', `Bearer ${token}`)
      .send({});
    expect(res.status).toBe(400);
  });

  it('rejects battery_level out of range', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .post('/api/v1/presence')
      .set('Authorization', `Bearer ${token}`)
      .send({ room_id: 3, battery_level: 200 });
    expect(res.status).toBe(400);
  });
});
