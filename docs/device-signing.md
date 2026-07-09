# Device Signing — Public-Key Request Verification

Aegis uses P-256 ECDSA signing to verify that a request originates from a registered physical device. The iPhone holds a private key (protected by the Secure Enclave); the server holds only the corresponding public key. For every protected request, the client attaches a signature over a canonical payload string. The server reconstructs the same string and verifies the signature.

This sits on top of the existing JWT authentication — both the `Authorization` header and the signature headers are required on protected routes.

---

## Key Facts

| Property | Value |
|---|---|
| Algorithm | P-256 ECDSA (secp256r1) |
| Hash | SHA-256 |
| Key storage (client) | iOS Secure Enclave |
| Public key format | Raw X9.63 uncompressed point (65 bytes), base64-encoded; server wraps into SPKI DER before verifying |
| Signature format | DER-encoded ECDSA signature, base64-encoded |
| One key pair per | user × device |

---

## Flow Overview

```
1. App first launch
   └─ Generate P-256 key pair in Secure Enclave
   └─ POST /api/v1/register-device  { device_public_key }
   └─ Server stores public key on USER record

2. Every protected request
   └─ Client builds canonical payload string
   └─ Client signs payload with private key
   └─ Client sends X-Timestamp + X-Signature headers (+ Authorization as usual)
   └─ Server verifies timestamp is fresh (±60 s)
   └─ Server verifies signature against stored public key
```

---

## Canonical Payload String

The client and server must produce the exact same string independently.

```
{METHOD}\n{PATH}\n{UNIX_TIMESTAMP_SECONDS}\n{SHA256_HEX(body)}
```

| Part | Description |
|---|---|
| `METHOD` | Uppercase HTTP method: `POST`, `GET`, … |
| `PATH` | Path only — no host, no query string: `/api/v1/presence` |
| `UNIX_TIMESTAMP_SECONDS` | Integer Unix epoch in seconds (same value sent in `X-Timestamp`) |
| `SHA256_HEX(body)` | Lowercase hex SHA-256 of the raw request body bytes. For requests with no body use the SHA-256 of zero bytes: `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |

**Example** — `POST /api/v1/presence` at timestamp `1720300000` with body `{"room_id":3}`:

```
POST\n/api/v1/presence\n1720300000\n7908b1690837f426aa17e210db69e2e5871630968643d69854db097f1a16d402
```

(This exact vector is locked by `Aegis-Backend/tests/lib/signingVector.test.ts`.)

---

## Request Headers

```
Authorization: Bearer <jwt>
X-Timestamp:  1720300000
X-Signature:  <base64(DER ECDSA signature)>
Content-Type: application/json   (when body is present)
```

---

## Client — Swift / CryptoKit

### 1. Key generation (run once on first launch)

```swift
import CryptoKit
import Foundation

// Generate key pair in the Secure Enclave.
// The private key never leaves the device hardware.
let privateKey = try SecureEnclave.P256.Signing.PrivateKey()

// Persist the key so it survives app restarts.
// Store privateKey.dataRepresentation in the Keychain with
// kSecAttrTokenIDSecureEnclave so it can be reloaded later:
//
//   let reloaded = try SecureEnclave.P256.Signing.PrivateKey(
//       dataRepresentation: storedData
//   )
```

### 2. Device registration (run once after key generation)

```swift
// Export the raw X9.63 uncompressed point (65 bytes: 0x04 || X || Y).
// The server wraps this into SPKI DER before verifying.
let publicKeyBase64 = privateKey.publicKey.x963Representation.base64EncodedString()

// POST /api/v1/register-device
// Body: { "device_public_key": publicKeyBase64 }
// Header: Authorization: Bearer <jwt>
```

### 3. Signing helper

```swift
import CryptoKit

func signRequest(
    method: String,
    path: String,
    body: Data,
    privateKey: SecureEnclave.P256.Signing.PrivateKey
) throws -> (xTimestamp: String, xSignature: String) {
    let timestamp = Int(Date().timeIntervalSince1970)

    let bodyHashHex = SHA256.hash(data: body)
        .map { String(format: "%02x", $0) }
        .joined()

    let payload = "\(method)\n\(path)\n\(timestamp)\n\(bodyHashHex)"
    let signature = try privateKey.signature(for: Data(payload.utf8))

    return (
        xTimestamp: "\(timestamp)",
        xSignature: signature.derRepresentation.base64EncodedString()
    )
}
```

### 4. Attaching headers to a URLRequest

```swift
var request = URLRequest(url: URL(string: "https://api.example.com/api/v1/presence")!)
request.httpMethod = "POST"

let body = try JSONEncoder().encode(presencePayload)
request.httpBody = body
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

let (ts, sig) = try signRequest(
    method: "POST",
    path: "/api/v1/presence",
    body: body,
    privateKey: privateKey
)
request.setValue(ts, forHTTPHeaderField: "X-Timestamp")
request.setValue(sig, forHTTPHeaderField: "X-Signature")
```

### Client — Notes

- For GET requests (no body) pass `Data()` as `body` — the SHA-256 of empty bytes is the constant above.
- If the user reinstalls the app, generate a new key pair and call `/api/v1/register-device` again. The new key overwrites the old one.
- Do not generate a new key pair on every launch — reload it from the Keychain using `dataRepresentation`.

---

## Server — Node.js / TypeScript

### Middleware: `requireSignature`

Location: `src/middleware/requireSignature.ts`

```typescript
import type { RequestHandler } from 'express';
import { createHash, createVerify } from 'node:crypto';
import { AppError } from '../lib/errors.js';
import { x963ToSpkiDer } from '../lib/deviceKey.js';
import { findUserById } from '../db/queries/userQueries.js';

const CLOCK_SKEW_MS = 60_000; // ±60 seconds

export const requireSignature: RequestHandler = async (req, _res, next) => {
  try {
    // requireAuth must run first — req.user is already set
    if (!req.user) return next(new AppError('unauthorized'));

    const tsHeader = req.headers['x-timestamp'];
    const sigHeader = req.headers['x-signature'];

    if (typeof tsHeader !== 'string' || typeof sigHeader !== 'string') {
      return next(new AppError('invalid_request', 'Missing X-Timestamp or X-Signature header'));
    }

    // 1. Validate timestamp freshness
    const timestamp = parseInt(tsHeader, 10);
    if (Number.isNaN(timestamp)) {
      return next(new AppError('invalid_request', 'X-Timestamp must be a Unix epoch integer'));
    }
    if (Math.abs(Date.now() - timestamp * 1000) > CLOCK_SKEW_MS) {
      return next(new AppError('invalid_request', 'Request timestamp is too old or too far in the future'));
    }

    // 2. Fetch stored public key
    const user = await findUserById(req.user.id);
    if (!user?.device_public_key) {
      return next(new AppError('forbidden', 'No device registered for this account'));
    }

    // 3. Reconstruct canonical payload. Use originalUrl (query stripped) — NOT
    //    req.path, which is relative to the router mount point (would be "/").
    const path = req.originalUrl.split('?')[0];
    const rawBody: Buffer = (req as unknown as { rawBody?: Buffer }).rawBody ?? Buffer.alloc(0);
    const bodyHash = createHash('sha256').update(rawBody).digest('hex');
    const payload = `${req.method}\n${path}\n${timestamp}\n${bodyHash}`;

    // 4. Verify signature. The stored key is a raw X9.63 point; wrap it into
    //    SPKI DER (see src/lib/deviceKey.ts) so Node's crypto can import it.
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

### Key wrapping: `src/lib/deviceKey.ts`

The client sends the public key as a raw X9.63 uncompressed point (65 bytes:
`0x04 || X || Y`). Node's `crypto.createVerify` needs an SPKI-DER key, so the
middleware wraps the raw point by prepending the fixed 26-byte P-256 SPKI
header (`3059301306072a8648ce3d020106082a8648ce3d030107034200`):

```typescript
export function x963ToSpkiDer(rawX963: Buffer): Buffer {
  if (rawX963.length !== 65 || rawX963[0] !== 0x04) {
    throw new AppError('forbidden', 'Malformed device public key');
  }
  return Buffer.concat([P256_SPKI_HEADER, rawX963]);
}
```

### Raw body preservation

`crypto.createVerify` must see the exact bytes the client hashed. Add this before routes in `app.ts`:

```typescript
app.use(express.json({
  limit: '64kb',
  verify: (req, _res, buf) => {
    (req as express.Request & { rawBody?: Buffer }).rawBody = buf;
  },
}));
```

### Applying the middleware to protected routes

Add `requireSignature` after `requireAuth` and `requireRole` on routes that need it:

```typescript
// presence.ts
import { requireSignature } from '../middleware/requireSignature.js';

presenceRouter.post(
  '/',
  requireAuth,
  requireRole('learner'),
  requireSignature,
  presenceRateLimit,
  async (req, res, next) => { /* handler */ }
);
```

`requireSignature` runs before `presenceRateLimit` so unsigned or forged
requests are rejected without consuming a caller's rate-limit budget.

Routes that should require a signature:
- `POST /api/v1/presence`
- `POST /api/v1/register-device` (except on first call — see note below)

> **Note on register-device**: the first call cannot be signature-verified because no key has been stored yet. Subsequent calls can be signed to prove the existing device is the one re-registering. For now, `/api/v1/register-device` is protected only by JWT; signature verification can be added as an optional second step later.

### Server — Column size

`USER.device_public_key` is `VARCHAR(256)`, ample for a base64-encoded raw
X9.63 P-256 point (~88 characters). Migration `0008` widens it (migration
`0007` originally created the column as `VARCHAR(64)`, which is too small).

---

## Error Responses

| Condition | HTTP | Code |
|---|---|---|
| Missing `X-Timestamp` or `X-Signature` | 400 | `invalid_request` |
| Timestamp outside ±60 s window | 400 | `invalid_request` |
| No public key registered for this user | 403 | `forbidden` |
| Signature does not verify | 403 | `forbidden` |
