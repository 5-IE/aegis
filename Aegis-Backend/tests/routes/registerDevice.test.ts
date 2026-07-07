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
  updateDevicePublicKey: vi.fn(),
}));

const buildTestApp = async () => {
  const { errorHandler } = await import('../../src/middleware/errorHandler.js');
  const { registerDeviceRouter } = await import('../../src/routes/registerDevice.js');
  const { signAccessToken } = await import('../../src/services/tokenService.js');
  const app = express();
  app.use(express.json());
  app.use('/api/v1/register-device', registerDeviceRouter);
  app.use(errorHandler);
  const token = signAccessToken({ sub: 42, role: 'learner', session: 'AM' });
  return { app, token };
};

beforeEach(() => vi.clearAllMocks());

describe('POST /register-device', () => {
  it('accepts an ~88-char base64 raw X9.63 key', async () => {
    const { app, token } = await buildTestApp();
    const q = await import('../../src/db/queries/userQueries.js');
    (q.updateDevicePublicKey as any).mockResolvedValue(undefined);
    const key = 'A'.repeat(88);
    const res = await request(app)
      .post('/api/v1/register-device')
      .set('Authorization', `Bearer ${token}`)
      .send({ device_public_key: key });
    expect(res.status).toBe(200);
    expect(q.updateDevicePublicKey).toHaveBeenCalledWith(42, key);
  });

  it('rejects a key longer than 256 chars', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .post('/api/v1/register-device')
      .set('Authorization', `Bearer ${token}`)
      .send({ device_public_key: 'A'.repeat(257) });
    expect(res.status).toBe(400);
  });

  it('rejects a missing key', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .post('/api/v1/register-device')
      .set('Authorization', `Bearer ${token}`)
      .send({});
    expect(res.status).toBe(400);
  });
});
