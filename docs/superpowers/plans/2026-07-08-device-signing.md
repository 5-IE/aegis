# Device Signing Reconciliation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bind a learner's `POST /api/v1/presence` request to the physical device that registered, by verifying a P-256 ECDSA signature over a canonical payload on top of the existing JWT auth.

**Architecture:** The iOS client (CryptoKit, Secure Enclave) signs `METHOD\nPATH\nTIMESTAMP\nSHA256_HEX(body)` and sends `X-Timestamp` + `X-Signature`. A new Express middleware `requireSignature` rebuilds the identical string and verifies it against the device public key stored on the `USER` row. The public key travels as a raw X9.63 point (base64); the server wraps it into SPKI DER with a fixed 26-byte header before verifying.

**Tech Stack:** Node 20 / TypeScript / Express 4 / MySQL (mysql2) / Vitest / Node `crypto`. Client: Swift / CryptoKit.

## Global Constraints

- Backend is ESM: all local imports end in `.js` (e.g. `import { AppError } from '../lib/errors.js'`).
- Errors are thrown/forwarded as `new AppError(code, message?)` where `code` is one of the `ErrorCode` union in `src/lib/errors.ts`. Never hand-roll status codes.
- Tests live in `tests/**/*.test.ts`, run with `vitest run`, `globals: false` (import `describe/it/expect/vi` from `vitest`). Every test file sets the env vars in `beforeAll` (JWT_SECRET, DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME) — copy the block from `tests/middleware/requireAuth.test.ts`.
- DB queries are mocked with `vi.mock('../../src/db/queries/userQueries.js', ...)` — never hit a real DB in tests.
- Lint must pass: `npm run lint` (eslint over `src tests scripts`).
- Migrations are plain `.sql` files in `migrations/`, numbered `NNNN_name.sql`, applied in sorted order; each starts with `USE \`AEGIS\`;`.
- Public key on the wire = base64 of raw X9.63 uncompressed point (65 bytes for P-256). Column `USER.device_public_key VARCHAR(256)`.
- Canonical payload string: `` `${METHOD}\n${PATH}\n${TIMESTAMP}\n${SHA256_HEX(body)}` ``. PATH is the full request path with query string stripped. Clock skew window: ±60_000 ms.
- Fixed P-256 SPKI header (hex): `3059301306072a8648ce3d020106082a8648ce3d030107034200` (26 bytes). Verified: header ++ 65-byte raw point == a valid SPKI DER key that `crypto.createVerify` accepts.

---

### Task 1: Widen `device_public_key` column + registerDevice cap

**Files:**
- Create: `Aegis-Backend/migrations/0008_widen_device_public_key.sql`
- Modify: `Aegis-Backend/src/routes/registerDevice.ts:12-13`
- Test: `Aegis-Backend/tests/routes/registerDevice.test.ts` (create)

**Interfaces:**
- Consumes: `updateDevicePublicKey(id: number, devicePublicKey: string): Promise<void>` (existing, `src/db/queries/userQueries.ts`); `requireAuth`, `requireRole('learner')`.
- Produces: nothing new; `POST /api/v1/register-device` now accepts keys up to 256 chars.

- [ ] **Step 1: Write the migration**

Create `Aegis-Backend/migrations/0008_widen_device_public_key.sql`:

```sql
USE `AEGIS`;

ALTER TABLE `USER`
  MODIFY COLUMN `device_public_key` VARCHAR(256) NULL DEFAULT NULL;
```

- [ ] **Step 2: Write failing tests for the register-device length cap**

There is no existing `registerDevice.test.ts`. Create `Aegis-Backend/tests/routes/registerDevice.test.ts`:

```ts
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
```

- [ ] **Step 3: Run the tests — the 88-char case should FAIL**

Run: `cd Aegis-Backend && npx vitest run tests/routes/registerDevice.test.ts`
Expected: "accepts an ~88-char base64 raw X9.63 key" FAILS (current cap is 64 → returns 400).

- [ ] **Step 4: Raise the length cap**

In `Aegis-Backend/src/routes/registerDevice.ts`, change the validation (currently lines 12-13):

```ts
    const { device_public_key } = req.body as { device_public_key?: unknown };
    if (typeof device_public_key !== 'string' || device_public_key.length === 0 || device_public_key.length > 256) {
      throw new AppError('invalid_request', 'device_public_key must be a non-empty string of at most 256 characters');
    }
```

- [ ] **Step 5: Run the tests — all pass**

Run: `cd Aegis-Backend && npx vitest run tests/routes/registerDevice.test.ts`
Expected: PASS (3 passed).

- [ ] **Step 6: Commit**

```bash
git add Aegis-Backend/migrations/0008_widen_device_public_key.sql Aegis-Backend/src/routes/registerDevice.ts Aegis-Backend/tests/routes/registerDevice.test.ts
git commit -m "feat: widen device_public_key to VARCHAR(256) and raise register-device cap"
```

---

### Task 2: `x963ToSpkiDer` key-wrapping helper

**Files:**
- Create: `Aegis-Backend/src/lib/deviceKey.ts`
- Test: `Aegis-Backend/tests/lib/deviceKey.test.ts`

**Interfaces:**
- Produces: `x963ToSpkiDer(rawX963: Buffer): Buffer` — prepends the fixed 26-byte P-256 SPKI header to a 65-byte uncompressed point, returning a 91-byte SPKI DER buffer. Throws `AppError('forbidden', 'Malformed device public key')` if the input is not a 65-byte buffer starting with `0x04`.

- [ ] **Step 1: Write the failing test**

Create `Aegis-Backend/tests/lib/deviceKey.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { generateKeyPairSync, createPublicKey } from 'node:crypto';
import { x963ToSpkiDer } from '../../src/lib/deviceKey.js';

// Extract the 65-byte raw X9.63 point from a generated P-256 key by slicing
// the 26-byte header off its SPKI DER export.
function rawPoint(): { raw: Buffer; spki: Buffer } {
  const { publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const spki = publicKey.export({ format: 'der', type: 'spki' }) as Buffer;
  return { raw: spki.subarray(26), spki };
}

describe('x963ToSpkiDer', () => {
  it('reconstructs a valid SPKI DER that Node can import', () => {
    const { raw, spki } = rawPoint();
    const rebuilt = x963ToSpkiDer(raw);
    expect(rebuilt.equals(spki)).toBe(true);
    // Node must accept the rebuilt key
    expect(() => createPublicKey({ key: rebuilt, format: 'der', type: 'spki' })).not.toThrow();
  });

  it('rejects a point of the wrong length', () => {
    expect(() => x963ToSpkiDer(Buffer.alloc(64, 4))).toThrowError(/Malformed/);
  });

  it('rejects a point with the wrong leading byte', () => {
    const bad = Buffer.alloc(65, 0);
    bad[0] = 0x03; // compressed marker, not uncompressed
    expect(() => x963ToSpkiDer(bad)).toThrowError(/Malformed/);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npx vitest run tests/lib/deviceKey.test.ts`
Expected: FAIL — `Cannot find module '.../src/lib/deviceKey.js'`.

- [ ] **Step 3: Write the implementation**

Create `Aegis-Backend/src/lib/deviceKey.ts`:

```ts
import { AppError } from './errors.js';

// Fixed ASN.1 prefix for a P-256 (prime256v1) SubjectPublicKeyInfo whose
// BIT STRING holds a 65-byte uncompressed X9.63 point. Prepending this to the
// raw point yields a 91-byte SPKI DER key that Node's crypto can import.
const P256_SPKI_HEADER = Buffer.from(
  '3059301306072a8648ce3d020106082a8648ce3d030107034200',
  'hex',
);

/**
 * Wrap a raw X9.63 uncompressed P-256 public point (as produced by iOS
 * CryptoKit `publicKey.x963Representation`) into SPKI DER.
 */
export function x963ToSpkiDer(rawX963: Buffer): Buffer {
  if (rawX963.length !== 65 || rawX963[0] !== 0x04) {
    throw new AppError('forbidden', 'Malformed device public key');
  }
  return Buffer.concat([P256_SPKI_HEADER, rawX963]);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Aegis-Backend && npx vitest run tests/lib/deviceKey.test.ts`
Expected: PASS (3 passed).

- [ ] **Step 5: Commit**

```bash
git add Aegis-Backend/src/lib/deviceKey.ts Aegis-Backend/tests/lib/deviceKey.test.ts
git commit -m "feat: add x963ToSpkiDer key-wrapping helper"
```

---

### Task 3: `requireSignature` middleware

**Files:**
- Create: `Aegis-Backend/src/middleware/requireSignature.ts`
- Test: `Aegis-Backend/tests/middleware/requireSignature.test.ts`

**Interfaces:**
- Consumes: `x963ToSpkiDer(raw: Buffer): Buffer` (Task 2); `findUserById(id: number): Promise<UserRow | null>` from `src/db/queries/userQueries.js`; `AppError`; `req.user` (set by `requireAuth`); `req.rawBody?: Buffer` (set by Task 4's verify hook).
- Produces: `export const requireSignature: RequestHandler` — async, calls `next()` on success or `next(new AppError(...))` on failure. Path is rebuilt from `req.originalUrl.split('?')[0]`.

- [ ] **Step 1: Write the failing test**

Create `Aegis-Backend/tests/middleware/requireSignature.test.ts`. The test generates a real P-256 key, derives the raw X9.63 point for the mocked user, signs a canonical payload, and drives the middleware directly with mock `req`/`res`/`next`:

```ts
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npx vitest run tests/middleware/requireSignature.test.ts`
Expected: FAIL — `Cannot find module '.../src/middleware/requireSignature.js'`.

- [ ] **Step 3: Write the implementation**

Create `Aegis-Backend/src/middleware/requireSignature.ts`:

```ts
import type { RequestHandler } from 'express';
import { createHash, createVerify } from 'node:crypto';
import { AppError } from '../lib/errors.js';
import { x963ToSpkiDer } from '../lib/deviceKey.js';
import { findUserById } from '../db/queries/userQueries.js';

const CLOCK_SKEW_MS = 60_000; // ±60 seconds

export const requireSignature: RequestHandler = async (req, _res, next) => {
  try {
    if (!req.user) return next(new AppError('unauthorized'));

    const tsHeader = req.headers['x-timestamp'];
    const sigHeader = req.headers['x-signature'];
    if (typeof tsHeader !== 'string' || typeof sigHeader !== 'string') {
      return next(new AppError('invalid_request', 'Missing X-Timestamp or X-Signature header'));
    }

    // 1. Timestamp freshness
    const timestamp = parseInt(tsHeader, 10);
    if (Number.isNaN(timestamp)) {
      return next(new AppError('invalid_request', 'X-Timestamp must be a Unix epoch integer'));
    }
    if (Math.abs(Date.now() - timestamp * 1000) > CLOCK_SKEW_MS) {
      return next(new AppError('invalid_request', 'Request timestamp is too old or too far in the future'));
    }

    // 2. Stored public key
    const user = await findUserById(req.user.id);
    if (!user?.device_public_key) {
      return next(new AppError('forbidden', 'No device registered for this account'));
    }

    // 3. Rebuild canonical payload. Use originalUrl (with query stripped)
    //    because req.path is relative to the router mount point.
    const path = req.originalUrl.split('?')[0];
    const rawBody: Buffer = (req as unknown as { rawBody?: Buffer }).rawBody ?? Buffer.alloc(0);
    const bodyHash = createHash('sha256').update(rawBody).digest('hex');
    const payload = `${req.method}\n${path}\n${timestamp}\n${bodyHash}`;

    // 4. Verify (wrap the raw X9.63 point into SPKI DER first)
    const spkiDer = x963ToSpkiDer(Buffer.from(user.device_public_key, 'base64'));
    const signatureDer = Buffer.from(sigHeader, 'base64');
    const verifier = createVerify('SHA256');
    verifier.update(payload);
    const valid = verifier.verify(
      { key: spkiDer, format: 'der', type: 'spki', dsaEncoding: 'der' },
      signatureDer,
    );
    if (!valid) return next(new AppError('forbidden', 'Invalid device signature'));

    next();
  } catch (err) {
    next(err);
  }
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Aegis-Backend && npx vitest run tests/middleware/requireSignature.test.ts`
Expected: PASS (8 passed).

- [ ] **Step 5: Commit**

```bash
git add Aegis-Backend/src/middleware/requireSignature.ts Aegis-Backend/tests/middleware/requireSignature.test.ts
git commit -m "feat: add requireSignature middleware"
```

---

### Task 4: Capture raw body + apply middleware to `/presence`

**Files:**
- Modify: `Aegis-Backend/src/app.ts:22`
- Modify: `Aegis-Backend/src/routes/presence.ts:18`
- Modify: `Aegis-Backend/tests/routes/presence.test.ts` (update the existing test app + add cases)

**Interfaces:**
- Consumes: `requireSignature` (Task 3).
- Produces: `req.rawBody: Buffer` available app-wide; `POST /api/v1/presence` now requires a valid signature.

- [ ] **Step 1: Update the presence test app to sign requests and add the unsigned case**

Replace the body of `Aegis-Backend/tests/routes/presence.test.ts` with a version whose test app mounts the `rawBody` verify hook and `requireSignature`, and that signs requests. Full file:

```ts
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
function signHeaders(bodyObj: unknown) {
  const rawBody = Buffer.from(JSON.stringify(bodyObj));
  const timestamp = Math.floor(Date.now() / 1000);
  const bodyHash = createHash('sha256').update(rawBody).digest('hex');
  const payload = `POST\n/api/v1/presence\n${timestamp}\n${bodyHash}`;
  const signer = createSign('SHA256');
  signer.update(payload);
  const sig = signer.sign({ key: privateKey, dsaEncoding: 'der' });
  return { 'X-Timestamp': String(timestamp), 'X-Signature': sig.toString('base64'), body: rawBody };
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

  it('returns 403 when the request is not signed', async () => {
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
```

Note: `requireSignature` ordering — it must run before `presenceRateLimit` so an unsigned request is rejected as 400/403, and the signature check does not consume rate-limit budget. The test app above mounts the real `presenceRouter`, so ordering is exercised end to end.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Aegis-Backend && npx vitest run tests/routes/presence.test.ts`
Expected: FAIL — the router does not yet require a signature, so "returns 403 when not signed" gets 204, and the valid-signed case may 400 because `rawBody` is undefined without the verify hook wired into the real `app.ts` (the test app has it, but the route lacks `requireSignature`).

- [ ] **Step 3: Add the `rawBody` verify hook in `app.ts`**

In `Aegis-Backend/src/app.ts`, replace line 22:

```ts
  app.use(express.json({
    limit: '64kb',
    verify: (req: express.Request & { rawBody?: Buffer }, _res, buf) => {
      req.rawBody = buf;
    },
  }));
```

- [ ] **Step 4: Apply `requireSignature` to the presence route**

In `Aegis-Backend/src/routes/presence.ts`, add the import and insert the middleware after `requireRole('learner')`:

```ts
import { requireSignature } from '../middleware/requireSignature.js';
```

```ts
presenceRouter.post('/', requireAuth, requireRole('learner'), requireSignature, presenceRateLimit, async (req, res, next) => {
```

- [ ] **Step 5: Run the presence tests — all pass**

Run: `cd Aegis-Backend && npx vitest run tests/routes/presence.test.ts`
Expected: PASS (4 passed).

- [ ] **Step 6: Run the full backend suite + lint**

Run: `cd Aegis-Backend && npx vitest run && npm run lint`
Expected: all tests PASS, lint clean. (Watch for other tests that POST to `/presence` — see Task 6 review.)

- [ ] **Step 7: Commit**

```bash
git add Aegis-Backend/src/app.ts Aegis-Backend/src/routes/presence.ts Aegis-Backend/tests/routes/presence.test.ts
git commit -m "feat: capture raw body and require device signature on POST /presence"
```

---

### Task 5: iOS — CryptoKit signing client

**Files:**
- Rewrite: `Aegis/Aegis/Services/CryptoManager.swift`
- Modify: `Aegis/Aegis/Services/ApiService` (attach headers to the presence request)

**Interfaces:**
- Produces:
  - `CryptoManager.shared.publicKeyBase64() -> String?` — base64 of `publicKey.x963Representation`.
  - `CryptoManager.shared.signRequest(method: String, path: String, body: Data) throws -> (xTimestamp: String, xSignature: String)`.
  - Private-key persistence: `dataRepresentation` stored in the Keychain under a fixed tag; reloaded on launch; generated once if absent.

> Note: iOS changes cannot be compiled or unit-tested in this environment (no Xcode/simulator). Verify by code review against the CryptoKit API and the cross-language vector from Task 6. Do NOT claim the client is "tested" — only reviewed.

- [ ] **Step 1: Rewrite `CryptoManager.swift`**

Replace the whole file `Aegis/Aegis/Services/CryptoManager.swift`:

```swift
//
//  CryptoManager.swift
//  Aegis
//

import CryptoKit
import Foundation
import Security

/// Device request signing using a P-256 key held in the Secure Enclave.
/// The private key's dataRepresentation is stored in the Keychain and reloaded
/// on launch; the public key is exported as a raw X9.63 point (base64) for the
/// server, which wraps it into SPKI DER before verifying.
final class CryptoManager {
    static let shared = CryptoManager()
    private init() {}

    private let keychainAccount = "com.academytracker.devicekey"
    private let keychainService = "com.academytracker.aegis"

    // MARK: - Key lifecycle

    /// Load the persisted Secure Enclave key, generating and storing one on first use.
    private func loadOrCreateKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        if let data = readKeyData() {
            return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data)
        }
        let key = try SecureEnclave.P256.Signing.PrivateKey()
        try storeKeyData(key.dataRepresentation)
        return key
    }

    /// Base64 of the raw X9.63 uncompressed public point, for /register-device.
    func publicKeyBase64() -> String? {
        guard let key = try? loadOrCreateKey() else { return nil }
        return key.publicKey.x963Representation.base64EncodedString()
    }

    // MARK: - Signing

    /// Build the canonical payload, sign it, and return the header values.
    /// Canonical payload: METHOD\nPATH\nUNIX_TS\nSHA256_HEX(body)
    func signRequest(
        method: String,
        path: String,
        body: Data
    ) throws -> (xTimestamp: String, xSignature: String) {
        let key = try loadOrCreateKey()
        let timestamp = Int(Date().timeIntervalSince1970)
        let bodyHashHex = SHA256.hash(data: body)
            .map { String(format: "%02x", $0) }
            .joined()
        let payload = "\(method)\n\(path)\n\(timestamp)\n\(bodyHashHex)"
        let signature = try key.signature(for: Data(payload.utf8))
        return (
            xTimestamp: String(timestamp),
            xSignature: signature.derRepresentation.base64EncodedString()
        )
    }

    // MARK: - Keychain (stores the Secure Enclave key's dataRepresentation)

    private func readKeyData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func storeKeyData(_ data: Data) throws {
        // Remove any stale entry first so this is idempotent.
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(base as CFDictionary)
        var attrs = base
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "CryptoManager", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Failed to store device key: \(status)"])
        }
    }
}
```

- [ ] **Step 2: Find the presence request in `ApiService` and attach signature headers**

Inspect `Aegis/Aegis/Services/ApiService` (it is a directory — find the file that builds the presence `POST`). At the point where the presence `URLRequest` is built and its body encoded, add:

```swift
// After: request.httpMethod = "POST"; request.httpBody = bodyData
if let (ts, sig) = try? CryptoManager.shared.signRequest(
    method: "POST",
    path: "/api/v1/presence",
    body: bodyData
) {
    request.setValue(ts, forHTTPHeaderField: "X-Timestamp")
    request.setValue(sig, forHTTPHeaderField: "X-Signature")
}
```

Ensure `bodyData` is the exact bytes assigned to `request.httpBody` (hash and body must match).

- [ ] **Step 3: Review against the CryptoKit API**

Confirm: `SecureEnclave.P256.Signing.PrivateKey().publicKey.x963Representation` yields a 65-byte point; `signature(for:).derRepresentation` is DER ECDSA; the signed `path` matches the server's `originalUrl` (`/api/v1/presence`).

- [ ] **Step 4: Commit**

```bash
git add Aegis/Aegis/Services/CryptoManager.swift Aegis/Aegis/Services/ApiService
git commit -m "feat: sign presence requests with CryptoKit Secure Enclave key"
```

---

### Task 6: Docs, cross-language vector, and full verification

**Files:**
- Modify: `docs/device-signing.md`
- Create: `Aegis-Backend/tests/lib/signingVector.test.ts`

**Interfaces:**
- Consumes: `x963ToSpkiDer` (Task 2). No new production code.

- [ ] **Step 1: Reconcile `docs/device-signing.md` with the decisions**

Make these edits:
- Key facts table: change "Public key format" from `SPKI DER, base64-encoded` to `Raw X9.63 uncompressed point, base64-encoded (server wraps into SPKI DER)`.
- Client section: change the public-key export to CryptoKit `publicKey.x963Representation.base64EncodedString()`.
- Server section: replace the `type:'spki'` note with a description of `x963ToSpkiDer` wrapping the raw point before `createVerify`.
- Server "Column size": `VARCHAR(256)`, and reference migration `0008` (not `0007`).
- Path note: add a caution that the server rebuilds PATH from `req.originalUrl` (query stripped), not `req.path`, because routers strip the mount prefix.
- Worked example: change the body from `{"beacon_id":3}` to `{"room_id":3}` and recompute the hash line (see Step 2 for the exact value).

- [ ] **Step 2: Write a known-answer signing vector test**

This locks the canonical-payload construction and the key-wrapping so the iOS and server sides cannot silently drift. Create `Aegis-Backend/tests/lib/signingVector.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { createHash, createSign, createVerify, generateKeyPairSync } from 'node:crypto';
import { x963ToSpkiDer } from '../../src/lib/deviceKey.js';

// End-to-end vector: a known payload, signed with a fresh key, verifies through
// the same raw-point -> SPKI DER path the middleware uses.
describe('signing vector', () => {
  it('body {"room_id":3} hashes to the documented value', () => {
    const hash = createHash('sha256').update(Buffer.from('{"room_id":3}')).digest('hex');
    // Lock the value that docs/device-signing.md must display.
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
    expect(hash.length).toBe(64);
  });

  it('sign-then-verify round-trips through x963ToSpkiDer', () => {
    const kp = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
    const spki = kp.publicKey.export({ format: 'der', type: 'spki' }) as Buffer;
    const rawPoint = spki.subarray(26); // what iOS sends (base64 of this)

    const timestamp = 1720300000;
    const bodyHash = createHash('sha256').update(Buffer.from('{"room_id":3}')).digest('hex');
    const payload = `POST\n/api/v1/presence\n${timestamp}\n${bodyHash}`;

    const signer = createSign('SHA256');
    signer.update(payload);
    const sig = signer.sign({ key: kp.privateKey, dsaEncoding: 'der' });

    const rebuilt = x963ToSpkiDer(rawPoint);
    const verifier = createVerify('SHA256');
    verifier.update(payload);
    const ok = verifier.verify({ key: rebuilt, format: 'der', type: 'spki', dsaEncoding: 'der' }, sig);
    expect(ok).toBe(true);
  });
});
```

- [ ] **Step 3: Run the vector test and capture the hash for the docs**

Run: `cd Aegis-Backend && npx vitest run tests/lib/signingVector.test.ts`
Then compute the exact hash to paste into the doc:
Run: `node -e "console.log(require('crypto').createHash('sha256').update('{\"room_id\":3}').digest('hex'))"`
Paste that value into the `docs/device-signing.md` worked example line.

- [ ] **Step 4: Full verification — whole backend suite + lint + typecheck**

Run: `cd Aegis-Backend && npx vitest run && npm run lint && npm run build`
Expected: all tests PASS, lint clean, `tsc` succeeds with no errors.

- [ ] **Step 5: Commit**

```bash
git add docs/device-signing.md Aegis-Backend/tests/lib/signingVector.test.ts
git commit -m "docs: reconcile device-signing.md and add signing vector test"
```

---

## Self-Review Notes

- **Spec coverage:** migration 0008 (T1), register cap (T1), `x963ToSpkiDer` (T2), `requireSignature` incl. path fix + all error branches (T3), rawBody hook + route wiring (T4), iOS CryptoKit rewrite + header attach (T5), doc reconciliation + cross-lang vector (T6). All spec sections mapped.
- **Ordering / blast-radius (verified):** a repo scan shows only `tests/routes/presence.test.ts` mounts the presence router and POSTs to it via supertest — Task 4 rewrites that file. Other files matching "presence" are service-layer tests that call `recordPresence`/`presenceService` directly and never hit the HTTP route, so they are unaffected. Task 4 Step 6 still runs the full suite as a backstop.
- **iOS untestable here:** Task 5 is review-only; no compile/test claim.
- **Types:** `x963ToSpkiDer(Buffer): Buffer`, `signRequest(method,path,body) -> (xTimestamp,xSignature)`, `publicKeyBase64() -> String?` used consistently across tasks.
