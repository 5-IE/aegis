import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';
import request from 'supertest';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

vi.mock('../../src/services/authService.js', () => ({
  login: vi.fn(),
  refresh: vi.fn(),
  logout: vi.fn(),
}));

const load = async () => {
  const app = (await import('../../src/app.js')).buildApp();
  const svc = await import('../../src/services/authService.js');
  const { AppError } = await import('../../src/lib/errors.js');
  return { app, svc, AppError };
};

beforeEach(() => vi.clearAllMocks());

describe('POST /auth/login', () => {
  it('returns 200 with tokens on success', async () => {
    const { app, svc } = await load();
    (svc.login as any).mockResolvedValue({
      accessToken: 'a', refreshToken: 'r', expiresIn: 900,
      user: { id: 1, username: 'alice', role: 'learner', session: 'AM', first_name: null, last_name: null, email: 'a@x' },
    });
    const res = await request(app)
      .post('/auth/login')
      .send({ username: 'alice', password: 'hunter2' });
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({
      access_token: 'a',
      refresh_token: 'r',
      expires_in: 900,
      user: { id: 1, role: 'learner' },
    });
  });

  it('returns 400 on missing password', async () => {
    const { app } = await load();
    const res = await request(app).post('/auth/login').send({ username: 'a' });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('invalid_request');
  });

  it('returns 401 on invalid credentials', async () => {
    const { app, svc, AppError } = await load();
    (svc.login as any).mockRejectedValue(new AppError('invalid_credentials'));
    const res = await request(app)
      .post('/auth/login')
      .send({ username: 'alice', password: 'wrong' });
    expect(res.status).toBe(401);
    expect(res.body.error).toBe('invalid_credentials');
  });
});

describe('POST /auth/refresh', () => {
  it('returns 200 with new tokens', async () => {
    const { app, svc } = await load();
    (svc.refresh as any).mockResolvedValue({
      accessToken: 'a2', refreshToken: 'r2', expiresIn: 900,
    });
    const res = await request(app).post('/auth/refresh').send({ refresh_token: 'r1' });
    expect(res.status).toBe(200);
    expect(res.body.access_token).toBe('a2');
  });

  it('returns 401 on invalid_grant', async () => {
    const { app, svc, AppError } = await load();
    (svc.refresh as any).mockRejectedValue(new AppError('invalid_grant'));
    const res = await request(app).post('/auth/refresh').send({ refresh_token: 'bogus' });
    expect(res.status).toBe(401);
    expect(res.body.error).toBe('invalid_grant');
  });

  it('returns 400 when refresh_token missing', async () => {
    const { app } = await load();
    const res = await request(app).post('/auth/refresh').send({});
    expect(res.status).toBe(400);
  });
});

describe('POST /auth/logout', () => {
  it('returns 204', async () => {
    const { app, svc } = await load();
    (svc.logout as any).mockResolvedValue(undefined);
    const res = await request(app).post('/auth/logout').send({ refresh_token: 'r' });
    expect(res.status).toBe(204);
    expect(svc.logout).toHaveBeenCalledWith('r');
  });

  it('returns 400 when refresh_token missing', async () => {
    const { app } = await load();
    const res = await request(app).post('/auth/logout').send({});
    expect(res.status).toBe(400);
  });
});
