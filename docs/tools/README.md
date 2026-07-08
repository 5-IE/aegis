# Device Signing — Test Tools

Tools for exercising the device-signing flow (`POST /api/v1/presence`) without a
physical iPhone. See [`../device-signing-end-to-end.md`](../device-signing-end-to-end.md)
for how the protocol works.

## `device-signing-tester.html` — the signing playground (recommended)

A fully client-side page that mirrors what the iOS app does: generates a P-256
key, registers it, builds the canonical payload, signs it, and produces a signed
request. Open it directly in a browser — **no server or build step needed**:

```
open docs/tools/device-signing-tester.html
```

Its crypto is verified against the real backend: WebCrypto's raw X9.63 public
key and the `p1363ToDer` signature converter produce signatures the shipped
`requireSignature` middleware accepts (checked across 300 random keys, including
the DER short-integer edge cases).

### How to use it

1. **Config** — set the Base URL (defaults to `http://10.64.50.204:3000`) and
   paste a **learner** JWT access token. Get one via `POST /auth/login` (curl or
   Postman) and copy `access_token`.
2. **Device key** — click *Generate / load key*. The key is saved in
   `localStorage` (the browser's stand-in for the Keychain), so it persists
   across reloads. The public key shown is the `device_public_key`.
3. **Register** — click *Register* to bind that public key to the JWT's user.
4. **Sign & send** — set method/path/body, click *Build signature*. You'll see
   the canonical payload, `X-Timestamp`, and `X-Signature`. Then either fire it
   live or copy the generated `curl`.

### Live fetch vs. curl

The backend has **no CORS** configured, so a browser `fetch` with custom headers
is blocked by the preflight. The **Show curl** buttons always work — copy the
command into a terminal. Live fetch only succeeds if CORS is enabled or the page
is served from the same origin as the API. For most testing, use curl.

## Manual curl (no tool at all)

If you already have a public key registered and a raw private key, you can sign
from Node. Adapt this snippet (Node 18+):

```js
import { createSign, createHash } from 'node:crypto';
const jwt = '...', ts = Math.floor(Date.now()/1000);
const body = '{"room_id":3}';                       // exact bytes you will send
const bodyHash = createHash('sha256').update(Buffer.from(body)).digest('hex');
const payload = `POST\n/api/v1/presence\n${ts}\n${bodyHash}`;
const sig = createSign('SHA256').update(payload)
  .sign({ key: myPrivateKeyPem, dsaEncoding: 'der' }).toString('base64');
console.log(`curl -X POST http://HOST:3000/api/v1/presence \\
  -H 'Authorization: Bearer ${jwt}' \\
  -H 'X-Timestamp: ${ts}' -H 'X-Signature: ${sig}' \\
  -H 'Content-Type: application/json' -d '${body}'`);
```

## Why not Postman for signing?

Postman *can* send the request, but its pre-request sandbox can't easily do
P-256/ECDSA signing (no first-class WebCrypto ECDSA, and it would need a bundled
crypto lib and manual r||s→DER conversion). The HTML tool does exactly this and
is verified against the server, so use it to produce the `X-Timestamp` /
`X-Signature` values, then paste them into Postman if you prefer that client.

The existing Postman collection (`../aegis.postman_collection.json`) still works
for the unsigned routes (login, register-device, admin, etc.).

## Expected results

| Response | Meaning |
|---|---|
| `204 No Content` | ✅ signature valid, presence recorded |
| `403 No device registered` | run Register first (same user as the JWT) |
| `403 Invalid device signature` | body-bytes or key mismatch |
| `400 invalid_request` | missing headers, or clock skew > 60 s |
