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

vi.mock('../../src/services/userService.js', () => ({
  listUsersService: vi.fn(),
  getUserService: vi.fn(),
  createUserService: vi.fn(),
  updateUserService: vi.fn(),
  resetPasswordService: vi.fn(),
  deleteUserService: vi.fn(),
  reactivateUserService: vi.fn(),
  toPublicUser: vi.fn(),
}));

const buildTestApp = async (role: 'admin' | 'learner' = 'admin', sub = 1) => {
  const { errorHandler } = await import('../../src/middleware/errorHandler.js');
  const { usersRouter } = await import('../../src/routes/admin/users.js');
  const { signAccessToken } = await import('../../src/services/tokenService.js');
  const app = express();
  app.use(express.json());
  app.use('/api/v1/admin/users', usersRouter);
  app.use(errorHandler);
  const token = signAccessToken({ sub, role });
  return { app, token };
};

beforeEach(() => vi.clearAllMocks());

describe('GET /api/v1/admin/users', () => {
  it('returns paged list', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/userService.js');
    (svc.listUsersService as any).mockResolvedValue({
      list: [], total: 0, page: 1, per_page: 20,
    });
    const res = await request(app)
      .get('/api/v1/admin/users?page=1&per_page=20')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.total).toBe(0);
  });

  it('rejects learner tokens with 403', async () => {
    const { app, token } = await buildTestApp('learner');
    const res = await request(app)
      .get('/api/v1/admin/users')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(403);
  });

  it('rejects invalid session filter with 400', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .get('/api/v1/admin/users?session=XX')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });

  it('passes include_inactive=false correctly (not silently true)', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/userService.js');
    (svc.listUsersService as any).mockResolvedValue({
      list: [], total: 0, page: 1, per_page: 20,
    });
    await request(app)
      .get('/api/v1/admin/users?include_inactive=false')
      .set('Authorization', `Bearer ${token}`);
    expect(svc.listUsersService).toHaveBeenCalledWith(
      expect.objectContaining({ includeInactive: false }),
      1,
      20,
    );
  });

  it('passes include_inactive=true correctly', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/userService.js');
    (svc.listUsersService as any).mockResolvedValue({
      list: [], total: 0, page: 1, per_page: 20,
    });
    await request(app)
      .get('/api/v1/admin/users?include_inactive=true')
      .set('Authorization', `Bearer ${token}`);
    expect(svc.listUsersService).toHaveBeenCalledWith(
      expect.objectContaining({ includeInactive: true }),
      1,
      20,
    );
  });

  it('rejects invalid include_inactive value with 400', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .get('/api/v1/admin/users?include_inactive=yes')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });
});

describe('GET /api/v1/admin/users/:id', () => {
  it('returns 200 on success', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/userService.js');
    (svc.getUserService as any).mockResolvedValue({ id: 42, username: 'a' });
    const res = await request(app)
      .get('/api/v1/admin/users/42')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.id).toBe(42);
  });

  it('returns 404 when user missing', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/userService.js');
    const { AppError } = await import('../../src/lib/errors.js');
    (svc.getUserService as any).mockRejectedValue(new AppError('not_found'));
    const res = await request(app)
      .get('/api/v1/admin/users/999')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });

  it('rejects non-numeric id with 400', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .get('/api/v1/admin/users/abc')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });
});

describe('POST /api/v1/admin/users', () => {
  it('returns 201 with the created user', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/userService.js');
    (svc.createUserService as any).mockResolvedValue({ id: 42, username: 'alice' });
    const res = await request(app)
      .post('/api/v1/admin/users')
      .set('Authorization', `Bearer ${token}`)
      .send({
        username: 'alice',
        password: 'hunter2',
        email: 'alice@example.com',
        role: 'learner',
        session: 'AM',
      });
    expect(res.status).toBe(201);
    expect(res.body.id).toBe(42);
  });

  it('returns 409 on conflict from service', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/userService.js');
    const { AppError } = await import('../../src/lib/errors.js');
    (svc.createUserService as any).mockRejectedValue(new AppError('conflict'));
    const res = await request(app)
      .post('/api/v1/admin/users')
      .set('Authorization', `Bearer ${token}`)
      .send({
        username: 'alice',
        password: 'hunter2',
        email: 'alice@example.com',
        role: 'learner',
        session: 'AM',
      });
    expect(res.status).toBe(409);
  });

  it('rejects body with unknown key (strict)', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .post('/api/v1/admin/users')
      .set('Authorization', `Bearer ${token}`)
      .send({
        username: 'alice',
        password: 'hunter2',
        email: 'alice@example.com',
        role: 'learner',
        session: 'AM',
        extra: 'bad',
      });
    expect(res.status).toBe(400);
  });

  it('rejects password > 72 chars', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .post('/api/v1/admin/users')
      .set('Authorization', `Bearer ${token}`)
      .send({
        username: 'alice',
        password: 'x'.repeat(73),
        email: 'alice@example.com',
        role: 'learner',
        session: 'AM',
      });
    expect(res.status).toBe(400);
  });
});

describe('PATCH /api/v1/admin/users/:id', () => {
  it('returns 200 with updated user', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/userService.js');
    (svc.updateUserService as any).mockResolvedValue({ id: 42, first_name: 'Alicia' });
    const res = await request(app)
      .patch('/api/v1/admin/users/42')
      .set('Authorization', `Bearer ${token}`)
      .send({ first_name: 'Alicia' });
    expect(res.status).toBe(200);
    expect(res.body.first_name).toBe('Alicia');
  });

  it('rejects password field in patch (must use dedicated endpoint)', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .patch('/api/v1/admin/users/42')
      .set('Authorization', `Bearer ${token}`)
      .send({ password: 'bad' });
    expect(res.status).toBe(400);
  });

  it('rejects username field in patch', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .patch('/api/v1/admin/users/42')
      .set('Authorization', `Bearer ${token}`)
      .send({ username: 'new-name' });
    expect(res.status).toBe(400);
  });

  it('rejects is_active field in patch', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .patch('/api/v1/admin/users/42')
      .set('Authorization', `Bearer ${token}`)
      .send({ is_active: false });
    expect(res.status).toBe(400);
  });
});

describe('PUT /api/v1/admin/users/:id/password', () => {
  it('returns 204 on success', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/userService.js');
    (svc.resetPasswordService as any).mockResolvedValue(undefined);
    const res = await request(app)
      .put('/api/v1/admin/users/42/password')
      .set('Authorization', `Bearer ${token}`)
      .send({ new_password: 'changeme' });
    expect(res.status).toBe(204);
    expect(svc.resetPasswordService).toHaveBeenCalledWith(42, 'changeme');
  });

  it('rejects missing new_password with 400', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .put('/api/v1/admin/users/42/password')
      .set('Authorization', `Bearer ${token}`)
      .send({});
    expect(res.status).toBe(400);
  });
});

describe('DELETE /api/v1/admin/users/:id', () => {
  it('returns 204 on success and passes requester id from JWT', async () => {
    const { app, token } = await buildTestApp('admin', 1);
    const svc = await import('../../src/services/userService.js');
    (svc.deleteUserService as any).mockResolvedValue(undefined);
    const res = await request(app)
      .delete('/api/v1/admin/users/42')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(204);
    expect(svc.deleteUserService).toHaveBeenCalledWith(42, 1);
  });

  it('returns 400 on self-delete (from service)', async () => {
    const { app, token } = await buildTestApp('admin', 1);
    const svc = await import('../../src/services/userService.js');
    const { AppError } = await import('../../src/lib/errors.js');
    (svc.deleteUserService as any).mockRejectedValue(new AppError('invalid_request'));
    const res = await request(app)
      .delete('/api/v1/admin/users/1')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });
});

describe('POST /api/v1/admin/users/:id/reactivate', () => {
  it('returns 204 on success', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/userService.js');
    (svc.reactivateUserService as any).mockResolvedValue(undefined);
    const res = await request(app)
      .post('/api/v1/admin/users/42/reactivate')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(204);
    expect(svc.reactivateUserService).toHaveBeenCalledWith(42);
  });

  it('returns 404 when user missing', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/userService.js');
    const { AppError } = await import('../../src/lib/errors.js');
    (svc.reactivateUserService as any).mockRejectedValue(new AppError('not_found'));
    const res = await request(app)
      .post('/api/v1/admin/users/999/reactivate')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });
});
