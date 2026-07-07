import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';
import request from 'supertest';
import express from 'express';
import { generateKeyPairSync, createSign, createHash, type KeyObject } from 'node:crypto';

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
vi.mock('../../src/db/queries/userQueries.js', () => ({
  findUserById: vi.fn(),
}));

let privateKey: KeyObject;
let deviceKeyB64: string;

beforeAll(() => {
  const kp = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  privateKey = kp.privateKey;
  const spki = kp.publicKey.export({ format: 'der', type: 'spki' }) as Buffer;
  deviceKeyB64 = spki.subarray(26).toString('base64');
});

const buildTestApp = async () => {
  const { errorHandler } = await import('../../src/middleware/errorHandler.js');
  const { presenceRouter } = await import('../../src/routes/presence.js');
  const { signAccessToken } = await import('../../src/services/tokenService.js');
  const app = express();
  app.use(express.json({ verify: (req: any, _res, buf) => { req.rawBody = buf; } }));
  app.use('/api/v1/presence', presenceRouter);
  app.use(errorHandler);
  const token = signAccessToken({ sub: 42, role: 'learner', session: 'AM' });
  return { app, token };
};

// Sign the canonical payload for a JSON body and return the headers.
// `body` is returned as a string so supertest sends the exact bytes we hashed
// (passing a Buffer would make supertest re-serialize it as {"type":"Buffer"...}).
function signHeaders(bodyObj: unknown) {
  const bodyStr = JSON.stringify(bodyObj);
  const timestamp = Math.floor(Date.now() / 1000);
  const bodyHash = createHash('sha256').update(Buffer.from(bodyStr)).digest('hex');
  const payload = `POST\n/api/v1/presence\n${timestamp}\n${bodyHash}`;
  const signer = createSign('SHA256');
  signer.update(payload);
  const sig = signer.sign({ key: privateKey, dsaEncoding: 'der' });
  return { 'X-Timestamp': String(timestamp), 'X-Signature': sig.toString('base64'), body: bodyStr };
}

beforeEach(() => vi.clearAllMocks());

describe('POST /presence', () => {
  it('returns 204 on a valid signed body', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/presenceService.js');
    const q = await import('../../src/db/queries/userQueries.js');
    (svc.recordPresence as any).mockResolvedValue(undefined);
    (q.findUserById as any).mockResolvedValue({ id_user: 42, device_public_key: deviceKeyB64 });
    const bodyObj = { room_id: 3, position_x: 1.5, position_y: 2.5, battery_level: 88 };
    const h = signHeaders(bodyObj);
    const res = await request(app)
      .post('/api/v1/presence')
      .set('Authorization', `Bearer ${token}`)
      .set('X-Timestamp', h['X-Timestamp'])
      .set('X-Signature', h['X-Signature'])
      .set('Content-Type', 'application/json')
      .send(h.body);
    expect(res.status).toBe(204);
    expect(svc.recordPresence).toHaveBeenCalledWith(42, bodyObj);
  });

  it('returns 400 when the request is not signed (missing headers)', async () => {
    const { app, token } = await buildTestApp();
    const q = await import('../../src/db/queries/userQueries.js');
    (q.findUserById as any).mockResolvedValue({ id_user: 42, device_public_key: deviceKeyB64 });
    const res = await request(app)
      .post('/api/v1/presence')
      .set('Authorization', `Bearer ${token}`)
      .send({ room_id: 3 });
    expect(res.status).toBe(400); // missing headers -> invalid_request
  });

  it('rejects missing room_id (400) on a signed request', async () => {
    const { app, token } = await buildTestApp();
    const q = await import('../../src/db/queries/userQueries.js');
    (q.findUserById as any).mockResolvedValue({ id_user: 42, device_public_key: deviceKeyB64 });
    const h = signHeaders({});
    const res = await request(app)
      .post('/api/v1/presence')
      .set('Authorization', `Bearer ${token}`)
      .set('X-Timestamp', h['X-Timestamp'])
      .set('X-Signature', h['X-Signature'])
      .set('Content-Type', 'application/json')
      .send(h.body);
    expect(res.status).toBe(400);
  });

  it('rejects battery_level out of range (400) on a signed request', async () => {
    const { app, token } = await buildTestApp();
    const q = await import('../../src/db/queries/userQueries.js');
    (q.findUserById as any).mockResolvedValue({ id_user: 42, device_public_key: deviceKeyB64 });
    const h = signHeaders({ room_id: 3, battery_level: 200 });
    const res = await request(app)
      .post('/api/v1/presence')
      .set('Authorization', `Bearer ${token}`)
      .set('X-Timestamp', h['X-Timestamp'])
      .set('X-Signature', h['X-Signature'])
      .set('Content-Type', 'application/json')
      .send(h.body);
    expect(res.status).toBe(400);
  });

  it('rejects a signed request from a user with no device key (403)', async () => {
    const { app, token } = await buildTestApp();
    const q = await import('../../src/db/queries/userQueries.js');
    (q.findUserById as any).mockResolvedValue({ id_user: 42, device_public_key: null });
    const h = signHeaders({ room_id: 3 });
    const res = await request(app)
      .post('/api/v1/presence')
      .set('Authorization', `Bearer ${token}`)
      .set('X-Timestamp', h['X-Timestamp'])
      .set('X-Signature', h['X-Signature'])
      .set('Content-Type', 'application/json')
      .send(h.body);
    expect(res.status).toBe(403);
  });
});
