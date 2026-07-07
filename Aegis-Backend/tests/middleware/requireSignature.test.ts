import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';
import type { Request, Response, NextFunction } from 'express';
import { generateKeyPairSync, createSign, createHash, type KeyObject } from 'node:crypto';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

vi.mock('../../src/db/queries/userQueries.js', () => ({
  findUserById: vi.fn(),
}));

// A P-256 key pair shared across tests; the public raw point becomes the
// mocked user's device_public_key.
let privateKey: KeyObject;
let deviceKeyB64: string;

beforeAll(() => {
  const kp = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  privateKey = kp.privateKey;
  const spki = kp.publicKey.export({ format: 'der', type: 'spki' }) as Buffer;
  deviceKeyB64 = spki.subarray(26).toString('base64'); // raw X9.63 point
});

const load = async () => {
  const { requireSignature } = await import('../../src/middleware/requireSignature.js');
  const q = await import('../../src/db/queries/userQueries.js');
  return { requireSignature, q };
};

function sha256Hex(buf: Buffer): string {
  return createHash('sha256').update(buf).digest('hex');
}

// Build a mock request + signature for the canonical payload.
function signedReq(opts: {
  method?: string;
  originalUrl?: string;
  timestamp?: number;
  rawBody?: Buffer;
  signWith?: KeyObject;
}) {
  const method = opts.method ?? 'POST';
  const originalUrl = opts.originalUrl ?? '/api/v1/presence';
  const timestamp = opts.timestamp ?? Math.floor(Date.now() / 1000);
  const rawBody = opts.rawBody ?? Buffer.from('{"room_id":3}');
  const path = originalUrl.split('?')[0];
  const payload = `${method}\n${path}\n${timestamp}\n${sha256Hex(rawBody)}`;
  const signer = createSign('SHA256');
  signer.update(payload);
  const sig = signer.sign({ key: opts.signWith ?? privateKey, dsaEncoding: 'der' });
  const req = {
    method,
    originalUrl,
    rawBody,
    user: { id: 42, role: 'learner' },
    headers: { 'x-timestamp': String(timestamp), 'x-signature': sig.toString('base64') },
  } as unknown as Request;
  return req;
}

const mockRes = () => ({} as Response);

beforeEach(() => vi.clearAllMocks());

describe('requireSignature', () => {
  it('calls next() with no error for a valid signature', async () => {
    const { requireSignature, q } = await load();
    (q.findUserById as any).mockResolvedValue({ id_user: 42, device_public_key: deviceKeyB64 });
    const req = signedReq({});
    const next = vi.fn() as unknown as NextFunction;
    await requireSignature(req, mockRes(), next);
    expect(next).toHaveBeenCalledWith();
  });

  it('rejects a stale timestamp with invalid_request', async () => {
    const { requireSignature, q } = await load();
    (q.findUserById as any).mockResolvedValue({ id_user: 42, device_public_key: deviceKeyB64 });
    const req = signedReq({ timestamp: Math.floor(Date.now() / 1000) - 120 });
    const next = vi.fn() as unknown as NextFunction;
    await requireSignature(req, mockRes(), next);
    expect((next as any).mock.calls[0][0].code).toBe('invalid_request');
  });

  it('rejects missing headers with invalid_request', async () => {
    const { requireSignature, q } = await load();
    (q.findUserById as any).mockResolvedValue({ id_user: 42, device_public_key: deviceKeyB64 });
    const req = { method: 'POST', originalUrl: '/api/v1/presence', rawBody: Buffer.from('{}'), user: { id: 42 }, headers: {} } as unknown as Request;
    const next = vi.fn() as unknown as NextFunction;
    await requireSignature(req, mockRes(), next);
    expect((next as any).mock.calls[0][0].code).toBe('invalid_request');
  });

  it('rejects a non-integer timestamp with invalid_request', async () => {
    const { requireSignature, q } = await load();
    (q.findUserById as any).mockResolvedValue({ id_user: 42, device_public_key: deviceKeyB64 });
    const req = signedReq({});
    (req.headers as any)['x-timestamp'] = 'not-a-number';
    const next = vi.fn() as unknown as NextFunction;
    await requireSignature(req, mockRes(), next);
    expect((next as any).mock.calls[0][0].code).toBe('invalid_request');
  });

  it('rejects when the user has no registered key with forbidden', async () => {
    const { requireSignature, q } = await load();
    (q.findUserById as any).mockResolvedValue({ id_user: 42, device_public_key: null });
    const req = signedReq({});
    const next = vi.fn() as unknown as NextFunction;
    await requireSignature(req, mockRes(), next);
    expect((next as any).mock.calls[0][0].code).toBe('forbidden');
  });

  it('rejects a tampered body with forbidden', async () => {
    const { requireSignature, q } = await load();
    (q.findUserById as any).mockResolvedValue({ id_user: 42, device_public_key: deviceKeyB64 });
    const req = signedReq({});
    (req as any).rawBody = Buffer.from('{"room_id":9999}'); // changed after signing
    const next = vi.fn() as unknown as NextFunction;
    await requireSignature(req, mockRes(), next);
    expect((next as any).mock.calls[0][0].code).toBe('forbidden');
  });

  it('rejects a signature from a different key with forbidden', async () => {
    const { requireSignature, q } = await load();
    (q.findUserById as any).mockResolvedValue({ id_user: 42, device_public_key: deviceKeyB64 });
    const other = generateKeyPairSync('ec', { namedCurve: 'prime256v1' }).privateKey;
    const req = signedReq({ signWith: other });
    const next = vi.fn() as unknown as NextFunction;
    await requireSignature(req, mockRes(), next);
    expect((next as any).mock.calls[0][0].code).toBe('forbidden');
  });

  it('rebuilds the path from originalUrl (query string stripped)', async () => {
    const { requireSignature, q } = await load();
    (q.findUserById as any).mockResolvedValue({ id_user: 42, device_public_key: deviceKeyB64 });
    // Sign for the bare path, then present a request whose originalUrl carries a query string.
    const req = signedReq({ originalUrl: '/api/v1/presence' });
    (req as any).originalUrl = '/api/v1/presence?debug=1';
    const next = vi.fn() as unknown as NextFunction;
    await requireSignature(req, mockRes(), next);
    expect(next).toHaveBeenCalledWith();
  });
});
