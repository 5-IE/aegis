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

vi.mock('../../src/services/roomsService.js', () => ({
  listAllRooms: vi.fn(),
  getRoomMap: vi.fn(),
  getRoomCurrentOccupants: vi.fn(),
  getRoomAdditionalData: vi.fn(),
}));

const buildTestApp = async () => {
  const { errorHandler } = await import('../../src/middleware/errorHandler.js');
  const { adminRoomsRouter } = await import('../../src/routes/admin/rooms.js');
  const { signAccessToken } = await import('../../src/services/tokenService.js');
  const app = express();
  app.use(express.json());
  app.use('/api/v1/admin/rooms', adminRoomsRouter);
  app.use(errorHandler);
  const token = signAccessToken({ sub: 1, role: 'admin' });
  return { app, token };
};

beforeEach(() => vi.clearAllMocks());

describe('GET /admin/rooms', () => {
  it('returns list', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/roomsService.js');
    (svc.listAllRooms as any).mockResolvedValue([{ id: 1, name: 'Lab A' }]);
    const res = await request(app).get('/api/v1/admin/rooms').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.list).toHaveLength(1);
  });
});

describe('GET /admin/rooms/:id/map', () => {
  it('returns 404 when room missing', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/roomsService.js');
    const { AppError } = await import('../../src/lib/errors.js');
    (svc.getRoomMap as any).mockRejectedValue(new AppError('not_found'));
    const res = await request(app).get('/api/v1/admin/rooms/99/map').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });

  it('rejects invalid id', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app).get('/api/v1/admin/rooms/abc/map').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });
});

describe('GET /admin/rooms/:id/current-occupants', () => {
  it('returns list', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/roomsService.js');
    (svc.getRoomCurrentOccupants as any).mockResolvedValue({ list: [] });
    const res = await request(app).get('/api/v1/admin/rooms/1/current-occupants').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
  });
});

describe('GET /admin/rooms/:id/additional-data', () => {
  it('returns readings', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/roomsService.js');
    (svc.getRoomAdditionalData as any).mockResolvedValue({ room_temperature: 24.5, humidity: 62, people_in_room: 3 });
    const res = await request(app).get('/api/v1/admin/rooms/1/additional-data').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.room_temperature).toBe(24.5);
  });
});
