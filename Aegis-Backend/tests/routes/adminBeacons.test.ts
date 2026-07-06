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

vi.mock('../../src/services/beaconsService.js', () => ({
  listBeaconsService: vi.fn(),
  getBeaconService: vi.fn(),
  createBeaconService: vi.fn(),
  updateBeaconService: vi.fn(),
  deleteBeaconService: vi.fn(),
  toBeaconResource: vi.fn(),
}));

const buildTestApp = async (role: 'admin' | 'learner' = 'admin', sub = 1) => {
  const { errorHandler } = await import('../../src/middleware/errorHandler.js');
  const { beaconsAdminRouter } = await import('../../src/routes/admin/beacons.js');
  const { signAccessToken } = await import('../../src/services/tokenService.js');
  const app = express();
  app.use(express.json());
  app.use('/api/v1/admin/beacons', beaconsAdminRouter);
  app.use(errorHandler);
  const token = signAccessToken({ sub, role });
  return { app, token };
};

beforeEach(() => vi.clearAllMocks());

describe('GET /api/v1/admin/beacons', () => {
  it('returns paged list', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    (svc.listBeaconsService as any).mockResolvedValue({
      list: [], total: 0, page: 1, per_page: 20,
    });
    const res = await request(app)
      .get('/api/v1/admin/beacons?page=1&per_page=20')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.total).toBe(0);
  });

  it('rejects learner with 403', async () => {
    const { app, token } = await buildTestApp('learner');
    const res = await request(app)
      .get('/api/v1/admin/beacons')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(403);
  });

  it('passes assigned=true correctly', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    (svc.listBeaconsService as any).mockResolvedValue({ list: [], total: 0, page: 1, per_page: 20 });
    await request(app)
      .get('/api/v1/admin/beacons?assigned=true')
      .set('Authorization', `Bearer ${token}`);
    expect(svc.listBeaconsService).toHaveBeenCalledWith(
      expect.objectContaining({ assigned: true }),
      1,
      20,
    );
  });

  it('passes assigned=false correctly', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    (svc.listBeaconsService as any).mockResolvedValue({ list: [], total: 0, page: 1, per_page: 20 });
    await request(app)
      .get('/api/v1/admin/beacons?assigned=false')
      .set('Authorization', `Bearer ${token}`);
    expect(svc.listBeaconsService).toHaveBeenCalledWith(
      expect.objectContaining({ assigned: false }),
      1,
      20,
    );
  });

  it('rejects invalid assigned value with 400', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .get('/api/v1/admin/beacons?assigned=yes')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });
});

describe('GET /api/v1/admin/beacons/:device_id', () => {
  it('returns 200 on success', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    (svc.getBeaconService as any).mockResolvedValue({ id: 1, name: 'iBeacon 1' });
    const res = await request(app)
      .get('/api/v1/admin/beacons/1')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.id).toBe(1);
  });

  it('returns 404 when device missing', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    const { AppError } = await import('../../src/lib/errors.js');
    (svc.getBeaconService as any).mockRejectedValue(new AppError('not_found'));
    const res = await request(app)
      .get('/api/v1/admin/beacons/999')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });

  it('rejects non-numeric id with 400', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .get('/api/v1/admin/beacons/abc')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });
});

describe('POST /api/v1/admin/beacons', () => {
  it('returns 201 with created beacon', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    (svc.createBeaconService as any).mockResolvedValue({ id: 1, name: 'iBeacon 1' });
    const res = await request(app)
      .post('/api/v1/admin/beacons')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'iBeacon 1', beacon_identifier: '1:1000', room_id: 3 });
    expect(res.status).toBe(201);
  });

  it('accepts room_id: null (unassigned)', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    (svc.createBeaconService as any).mockResolvedValue({ id: 2, name: 'Spare' });
    const res = await request(app)
      .post('/api/v1/admin/beacons')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Spare', beacon_identifier: '1:9999', room_id: null });
    expect(res.status).toBe(201);
    expect(svc.createBeaconService).toHaveBeenCalledWith({
      name: 'Spare', beacon_identifier: '1:9999', room_id: null,
    });
  });

  it('returns 409 on conflict', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    const { AppError } = await import('../../src/lib/errors.js');
    (svc.createBeaconService as any).mockRejectedValue(new AppError('conflict'));
    const res = await request(app)
      .post('/api/v1/admin/beacons')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'x', beacon_identifier: '1:1000', room_id: 3 });
    expect(res.status).toBe(409);
  });

  it('rejects unknown keys with 400 (strict)', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .post('/api/v1/admin/beacons')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'x', beacon_identifier: '1:1000', room_id: 3, extra: 'bad' });
    expect(res.status).toBe(400);
  });

  it('rejects missing required fields with 400', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .post('/api/v1/admin/beacons')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'x' });
    expect(res.status).toBe(400);
  });

  it('accepts create without room_id (defaults to null unassigned)', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    (svc.createBeaconService as any).mockResolvedValue({ id: 3, name: 'Spare2', beacon_identifier: '1:8888', room_id: null, room_name: null });
    const res = await request(app)
      .post('/api/v1/admin/beacons')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Spare2', beacon_identifier: '1:8888' });
    expect(res.status).toBe(201);
    expect(svc.createBeaconService).toHaveBeenCalledWith({
      name: 'Spare2',
      beacon_identifier: '1:8888',
      room_id: null,
    });
  });
});

describe('PATCH /api/v1/admin/beacons/:device_id', () => {
  it('returns 200 with updated beacon', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    (svc.updateBeaconService as any).mockResolvedValue({ id: 1, name: 'renamed' });
    const res = await request(app)
      .patch('/api/v1/admin/beacons/1')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'renamed' });
    expect(res.status).toBe(200);
    expect(svc.updateBeaconService).toHaveBeenCalledWith(1, { name: 'renamed' });
  });

  it('accepts room_id: null in patch', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    (svc.updateBeaconService as any).mockResolvedValue({ id: 1, room_id: null });
    const res = await request(app)
      .patch('/api/v1/admin/beacons/1')
      .set('Authorization', `Bearer ${token}`)
      .send({ room_id: null });
    expect(res.status).toBe(200);
    expect(svc.updateBeaconService).toHaveBeenCalledWith(1, { room_id: null });
  });

  it('rejects unknown keys with 400', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .patch('/api/v1/admin/beacons/1')
      .set('Authorization', `Bearer ${token}`)
      .send({ id_device: 99 });
    expect(res.status).toBe(400);
  });
});

describe('DELETE /api/v1/admin/beacons/:device_id', () => {
  it('returns 204 on success', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    (svc.deleteBeaconService as any).mockResolvedValue(undefined);
    const res = await request(app)
      .delete('/api/v1/admin/beacons/1')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(204);
  });

  it('returns 404 when device missing', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    const { AppError } = await import('../../src/lib/errors.js');
    (svc.deleteBeaconService as any).mockRejectedValue(new AppError('not_found'));
    const res = await request(app)
      .delete('/api/v1/admin/beacons/999')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });
});
