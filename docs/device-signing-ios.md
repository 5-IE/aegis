# Device Signing — iOS Implementation Guide

How to make the Aegis iOS app sign protected requests so they pass the backend's
`requireSignature` middleware. The backend side is already shipped; this guide is
the client half.

Read `docs/device-signing.md` first for the protocol. This guide is the concrete
Swift plan for **this** app, referencing the files as they exist today.

---

## What the server expects

For every protected request (currently `POST /api/v1/presence`) the client must:

1. Register a device public key once, as **base64 of the raw X9.63 point** (65
   bytes: `0x04 || X || Y`), via `POST /api/v1/register-device`.
2. On each protected request, attach two headers computed from a canonical
   payload string:

```
X-Timestamp:  <unix epoch seconds, integer>
X-Signature:  <base64( DER ECDSA signature )>
```

Canonical payload that gets signed (must match the server byte-for-byte):

```
{METHOD}\n{PATH}\n{UNIX_TIMESTAMP_SECONDS}\n{SHA256_HEX(body)}
```

- `METHOD` — uppercase (`POST`)
- `PATH` — path only, no host, no query string (`/api/v1/presence`)
- `UNIX_TIMESTAMP_SECONDS` — the same integer sent in `X-Timestamp`
- `SHA256_HEX(body)` — lowercase hex SHA-256 of the **exact request body bytes**.
  Empty body → SHA-256 of zero bytes:
  `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`

**Freshness:** the server rejects a timestamp outside ±60 s. The device clock
must be roughly correct.

### Known-answer vector (verify your implementation against this)

Body `{"room_id":3}` at timestamp `1720300000` for `POST /api/v1/presence`:

```
body SHA-256 = 7908b1690837f426aa17e210db69e2e5871630968643d69854db097f1a16d402
payload      = POST\n/api/v1/presence\n1720300000\n7908b1690837f426aa17e210db69e2e5871630968643d69854db097f1a16d402
```

If your Swift `SHA256` of `{"room_id":3}` doesn't equal that hex, stop and fix
the hashing before touching signatures. This vector is locked by
`Aegis-Backend/tests/lib/signingVector.test.ts`.

---

## Current iOS state (what exists today)

- `Aegis/Aegis/Services/CryptoManager.swift` — Security-framework based
  (`SecKeyCreateRandomKey`), exposes `generateDeviceKeyPair()`,
  `getPublicKeyBase64()`, `loadPrivateKey()`, `sign(serverChallenge:)`.
- `Aegis/Aegis/Services/ApiService/HttpService.swift` — a single generic
  `request(_:endpoint:params:queryParams:isRetry:)` that builds every request
  and sets `httpBody` via `JSONSerialization.data(withJSONObject: params)`.
- `Aegis/Aegis/Services/ApiService/ApiService.swift` — typed endpoints
  (`login`, `refreshToken`, `registerDevice`, `fetchProfile`, `fetchDashboard`,
  `fetchAttendanceHistory`). **No presence endpoint yet.**
- `Aegis/Aegis/ViewModels/RegisterViewModel.swift` — generates a key and only
  `print`s the public key; it **never calls** `apiService.registerDevice`.

So three things are needed: (a) a CryptoKit-based signer, (b) actually wiring
registration, and (c) a presence request that carries the signature headers.

> **Why the existing key export won't work as-is:** `getPublicKeyBase64()` uses
> `SecKeyCopyExternalRepresentation`, which returns the raw X9.63 point — that
> part is compatible with the server. But `sign(serverChallenge:)` signs an
> arbitrary string, which is the wrong scheme. The rewrite below replaces the
> signing path while keeping the raw-X9.63 public key format.

---

## Implementation plan

### Step 1 — Rewrite `CryptoManager` with CryptoKit

Replace `Aegis/Aegis/Services/CryptoManager.swift`. Uses
`SecureEnclave.P256.Signing.PrivateKey`, persists the key's
`dataRepresentation` in the Keychain, and reloads it on launch.

```swift
//
//  CryptoManager.swift
//  Aegis
//

import CryptoKit
import Foundation
import Security

/// Device request signing with a P-256 key held in the Secure Enclave.
/// The private key's `dataRepresentation` is stored in the Keychain and
/// reloaded on launch. The public key is exported as a raw X9.63 point
/// (base64); the server wraps it into SPKI DER before verifying.
final class CryptoManager {
    static let shared = CryptoManager()
    private init() {}

    private let keychainService = "com.academytracker.aegis"
    private let keychainAccount = "com.academytracker.devicekey"

    // MARK: - Key lifecycle

    /// Load the persisted Secure Enclave key, generating + storing one on first use.
    private func loadOrCreateKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        if let data = readKeyData() {
            return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data)
        }
        let key = try SecureEnclave.P256.Signing.PrivateKey()
        try storeKeyData(key.dataRepresentation)
        return key
    }

    /// Base64 of the raw X9.63 uncompressed public point — for /register-device.
    func publicKeyBase64() -> String? {
        guard let key = try? loadOrCreateKey() else { return nil }
        return key.publicKey.x963Representation.base64EncodedString()
    }

    // MARK: - Signing

    /// Build the canonical payload, sign it, return the header values.
    /// Payload: METHOD\nPATH\nUNIX_TS\nSHA256_HEX(body)
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
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(base as CFDictionary) // idempotent overwrite
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

**Callers to update after this rewrite** (the old method names are gone):
- `RegisterViewModel.swift:24` `generateDeviceKeyPair()` → removed
- `RegisterViewModel.swift:30` `getPublicKeyBase64()` → `publicKeyBase64()`

> **Secure Enclave availability:** `SecureEnclave.isAvailable` is `false` on the
> simulator and very old devices. For simulator/dev builds, fall back to a plain
> `P256.Signing.PrivateKey` (no enclave) behind the same interface, or gate the
> feature. Do not ship the fallback to production without review.

### Step 2 — Actually register the device key

Fix `RegisterViewModel.registerDevice()` to upload the key instead of printing it.

```swift
func registerDevice() {
    self.isLoading = true
    self.errorMessage = nil

    Task {
        guard let publicKeyBase64 = CryptoManager.shared.publicKeyBase64() else {
            self.errorMessage = "Failed to generate or load the device key."
            self.isLoading = false
            return
        }
        do {
            _ = try await apiService.registerDevice(publicKey: publicKeyBase64)
            self.isRegistered = true
        } catch {
            self.errorMessage = "Device registration failed: \(error.localizedDescription)"
        }
        self.isLoading = false
    }
}
```

`ApiService.registerDevice(publicKey:)` already exists and posts
`{ "device_public_key": publicKey }` to `/api/v1/register-device` — no change
needed there.

### Step 3 — Sign requests inside `HttpService`

Signing must hook the one generic `request()` so the bytes hashed are exactly
the bytes sent. Compute `bodyData` once, set it as `httpBody`, then sign it.

In `HttpService.request(...)`, replace the body-setting block:

```swift
// BEFORE:
// if let params = params {
//     request.httpBody = try? JSONSerialization.data(withJSONObject: params)
// }

// AFTER:
let bodyData: Data = (params != nil)
    ? ((try? JSONSerialization.data(withJSONObject: params!)) ?? Data())
    : Data()
if params != nil {
    request.httpBody = bodyData
}

// Sign protected requests. `endpoint` is the path the server signs against
// (it mounts routers at /api/v1/...), so pass it verbatim — no host, no query.
if requiresSignature(endpoint) {
    if let (ts, sig) = try? CryptoManager.shared.signRequest(
        method: method,
        path: endpoint,
        body: bodyData
    ) {
        request.setValue(ts, forHTTPHeaderField: "X-Timestamp")
        request.setValue(sig, forHTTPHeaderField: "X-Signature")
    }
}
```

Add a small allowlist so only protected endpoints get signed (signing every
request is harmless but wasteful, and the server only checks `/presence` today):

```swift
private func requiresSignature(_ endpoint: String) -> Bool {
    return endpoint == "/api/v1/presence"
}
```

**Critical:** `path` passed to `signRequest` must equal what the server rebuilds
from `req.originalUrl` — i.e. the full `/api/v1/presence`, with **no query
string**. If you ever add query params to a signed endpoint, strip them from the
`path` before signing (the server does `originalUrl.split('?')[0]`).

### Step 4 — Add the presence request

There is no presence endpoint on iOS yet. Add one to `ApiServiceProtocol` +
`ApiService`:

```swift
// ApiServiceProtocol
func sendPresence(roomId: Int,
                  positionX: Double?,
                  positionY: Double?,
                  batteryLevel: Int?) async throws -> EmptyResponse

// ApiService
func sendPresence(roomId: Int,
                  positionX: Double?,
                  positionY: Double?,
                  batteryLevel: Int?) async throws -> EmptyResponse {
    var params: [String: Any] = ["room_id": roomId]
    if let positionX { params["position_x"] = positionX }
    if let positionY { params["position_y"] = positionY }
    if let batteryLevel { params["battery_level"] = batteryLevel }
    return try await request("POST", endpoint: "/api/v1/presence", params: params)
}
```

The server body schema is `{ room_id (required, positive int), position_x?,
position_y?, battery_level? (0–100) }` and responds `204 No Content` on success.

---

## Body-bytes gotcha (the #1 source of 403s)

The signature covers `SHA256(body bytes)`. The hash on the client and the bytes
received by the server **must be identical**. Two traps:

1. **Re-serialization.** If any layer re-encodes the JSON between hashing and
   sending (e.g. hashing a Swift dict but letting URLSession serialize
   separately), key ordering or spacing can differ and the hash won't match.
   The Step 3 code avoids this by hashing the exact `bodyData` it assigns to
   `httpBody`.
2. **Empty body.** For a request with no body, sign `Data()` — its SHA-256 is
   the empty-bytes constant above. Don't sign `nil` or a `{}` object.

`JSONSerialization` does not guarantee key order, but that's fine as long as the
**same bytes** are both hashed and sent — the server hashes whatever bytes
arrive, it does not re-parse and re-serialize.

---

## Error responses to handle

| Server response | Meaning | Client action |
|---|---|---|
| `400 invalid_request` | Missing/'`X-Timestamp`/`X-Signature`, or bad timestamp | Bug in signing path or device clock skew |
| `403 forbidden` (No device registered) | No key stored for this user | Re-run registration (Step 2) |
| `403 forbidden` (Invalid device signature) | Signature/body mismatch | Check body-bytes gotcha; verify key format |
| `204 No Content` | Success | — |

If registration was done before the backend column was widened (migration
`0008`), the old key was truncated/rejected — re-register once on the new build.

---

## Verification checklist

- [ ] `SHA256("{\"room_id\":3}")` in Swift equals the known-answer hex above.
- [ ] `publicKeyBase64()` returns ~88 base64 chars (65-byte raw point).
- [ ] Registration returns success and the key persists across app restarts
      (reloaded from Keychain, not regenerated).
- [ ] A real signed `POST /api/v1/presence` returns `204`.
- [ ] Tampering with the body after signing yields `403` (sanity check).
- [ ] Reinstall → new key generated → re-register → presence works again.

---

## Notes & scope

- **One key per user × device.** Reinstalling regenerates the key; re-register.
- **Replay window:** requests are replayable within ±60 s (no nonce). Accepted
  trade-off, mirrored on the server; per-user rate limiting bounds abuse.
- **register-device stays JWT-only** — the first registration can't be
  signature-verified because no key exists yet.
- Keep `path` and `method` exactly aligned with the server route. A signature
  for `GET`/a different path is correctly rejected (the server binds both into
  the payload).
