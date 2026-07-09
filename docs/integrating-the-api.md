# Integrating the Aegis API

This guide is for developers building the iPhone (learner) and macOS (admin) apps against the Aegis backend. It walks through authentication, calling endpoints, refreshing tokens, and the presence-ping flow — with both `curl` (for quick manual testing) and Swift `URLSession` examples.

Before you start, make sure the backend is running locally per [Getting Started](getting-started.md). Every example assumes `http://localhost:3000`. Point at your deployed URL when the time comes.

For the full endpoint catalogue with every field and status code, open [`api-reference.html`](api-reference.html) in a browser.

---

## Mental model

- **Every request is JSON.** Send `Content-Type: application/json` and a JSON body where required.
- **Every response is JSON**, including errors.
- **Two token types:**
  - **Access token** — short-lived (15 min), sent on every protected request as `Authorization: Bearer <token>`.
  - **Refresh token** — long-lived (30 days), sent only to `/auth/refresh` and `/auth/logout`. Never send it as `Authorization`.
- **Roles.** Every user has a role: `learner` or `admin`. Endpoints under `/api/v1/admin/*` require an admin token; most others require a learner token; `/api/v1/beacons` accepts either.

---

## Auth flow

The complete lifecycle:

```
   iPhone/Mac App                    Aegis Backend
        │                                  │
        │  POST /auth/login                │
        │  { username, password }          │
        │─────────────────────────────────▶│
        │◀── { access_token,               │
        │      refresh_token,              │
        │      expires_in: 900,            │
        │      user: {...} }               │
        │                                  │
        │  ── save both tokens ──          │
        │                                  │
        │  GET /api/v1/dashboard           │
        │  Authorization: Bearer <at>      │
        │─────────────────────────────────▶│
        │◀── { total_attendance, ... }     │
        │                                  │
        │  ─── 15 minutes pass ───         │
        │                                  │
        │  GET /api/v1/dashboard           │
        │  Authorization: Bearer <at>      │
        │─────────────────────────────────▶│
        │◀── 401 unauthorized              │
        │                                  │
        │  POST /auth/refresh              │
        │  { refresh_token }               │
        │─────────────────────────────────▶│
        │◀── { access_token,               │  (new pair — old refresh_token
        │      refresh_token,              │   is now invalid)
        │      expires_in: 900 }           │
        │                                  │
        │  ── replace both tokens ──       │
        │                                  │
        │  GET /api/v1/dashboard           │
        │  Authorization: Bearer <new-at>  │
        │─────────────────────────────────▶│
        │◀── { total_attendance, ... }     │
```

**Key rules:**
- Store both tokens. On iOS and macOS, use the **Keychain** for `refresh_token` — never `UserDefaults` or a plain file.
- The `access_token` can live in memory only; if the app relaunches, refresh to get a new one.
- When a call returns `401 unauthorized`, try refreshing once. If refresh also fails, the user must log in again.
- **Refresh tokens rotate.** Every successful `/auth/refresh` returns a NEW `refresh_token` and invalidates the old one. If you present a used-up refresh token, the server assumes theft and revokes ALL your refresh tokens — user is logged out everywhere.

---

## Step 1 — Log in

### curl

```bash
curl -X POST http://localhost:3000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"changeme"}'
```

Response:

```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "refresh_token": "5f4b7c...base64url",
  "expires_in": 900,
  "user": {
    "id": 1,
    "username": "admin",
    "role": "admin",
    "session": "AM",
    "first_name": null,
    "last_name": null,
    "email": "admin@aegis.local"
  }
}
```

### Swift (URLSession)

```swift
import Foundation

struct LoginRequest: Encodable {
    let username: String
    let password: String
}

struct LoginResponse: Decodable {
    let access_token: String
    let refresh_token: String
    let expires_in: Int
    let user: User

    struct User: Decodable {
        let id: Int
        let username: String
        let role: String
        let session: String?
        let first_name: String?
        let last_name: String?
        let email: String
    }
}

func login(username: String, password: String) async throws -> LoginResponse {
    let url = URL(string: "http://localhost:3000/auth/login")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(
        LoginRequest(username: username, password: password)
    )

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        // handle error — see Error handling section below
        throw URLError(.badServerResponse)
    }
    return try JSONDecoder().decode(LoginResponse.self, from: data)
}
```

Persist `refresh_token` in the Keychain immediately:

```swift
// Sketch — use your Keychain wrapper of choice (KeychainAccess, etc.)
Keychain.shared.set(response.refresh_token, forKey: "aegis.refresh_token")
```

---

## Step 2 — Call a protected endpoint

Every request under `/api/v1/*` needs the access token.

### curl

```bash
ACCESS_TOKEN="eyJhbGciOiJIUzI1NiIs..."   # from the login response

curl http://localhost:3000/api/v1/me \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

Response:

```json
{
  "id": 1,
  "first_name": null,
  "last_name": null,
  "username": "admin",
  "email": "admin@aegis.local",
  "role": "admin",
  "session": "AM"
}
```

### Swift

```swift
func getMe(accessToken: String) async throws -> Data {
    let url = URL(string: "http://localhost:3000/api/v1/me")!
    var request = URLRequest(url: url)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    let (data, _) = try await URLSession.shared.data(for: request)
    return data
}
```

---

## Step 3 — Refresh when the access token expires

### curl

```bash
REFRESH_TOKEN="5f4b7c...base64url"

curl -X POST http://localhost:3000/auth/refresh \
  -H "Content-Type: application/json" \
  -d "{\"refresh_token\":\"$REFRESH_TOKEN\"}"
```

Response has the same shape as login except no `user` object:

```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "refresh_token": "9c1a2f...base64url",
  "expires_in": 900
}
```

**Replace BOTH tokens after every refresh.** The old refresh token is now invalid.

### Swift

```swift
struct RefreshRequest: Encodable { let refresh_token: String }
struct RefreshResponse: Decodable {
    let access_token: String
    let refresh_token: String
    let expires_in: Int
}

func refresh(refreshToken: String) async throws -> RefreshResponse {
    let url = URL(string: "http://localhost:3000/auth/refresh")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(RefreshRequest(refresh_token: refreshToken))

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        // 401 invalid_grant = refresh failed → user must log in again
        throw URLError(.userAuthenticationRequired)
    }
    return try JSONDecoder().decode(RefreshResponse.self, from: data)
}
```

### Pattern: auto-refresh on 401

In production, wrap your API calls so a 401 triggers one refresh attempt before failing:

```swift
func authorized<T: Decodable>(_ request: URLRequest, decodeTo: T.Type) async throws -> T {
    var attempt = request
    attempt.setValue("Bearer \(tokenStore.accessToken)", forHTTPHeaderField: "Authorization")

    var (data, response) = try await URLSession.shared.data(for: attempt)

    if (response as? HTTPURLResponse)?.statusCode == 401 {
        // Try refresh once
        let refreshed = try await refresh(refreshToken: tokenStore.refreshToken)
        tokenStore.set(access: refreshed.access_token, refresh: refreshed.refresh_token)

        attempt.setValue("Bearer \(refreshed.access_token)", forHTTPHeaderField: "Authorization")
        (data, response) = try await URLSession.shared.data(for: attempt)
    }
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw URLError(.badServerResponse)
    }
    return try JSONDecoder().decode(T.self, from: data)
}
```

---

## Step 4 — Log out

Revokes the refresh token so it can't be used again. The current access token stays valid for up to 15 minutes — that's an accepted tradeoff. Drop the tokens from your local storage as well.

### curl

```bash
curl -X POST http://localhost:3000/auth/logout \
  -H "Content-Type: application/json" \
  -d "{\"refresh_token\":\"$REFRESH_TOKEN\"}"
```

Response: `204 No Content` (empty body). Idempotent — calling it with an already-revoked token also returns 204.

---

## Presence ping flow (iPhone learner app)

The most important flow for the iPhone app. Two phases:

### Phase A (once at app startup, or when beacons might have changed)

Fetch the beacon → room mapping and cache it locally.

```bash
curl http://localhost:3000/api/v1/beacons \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

Response:

```json
{
  "list": [
    { "beacon_identifier": "1:2", "room_id": 3, "position_x": 0.25, "position_y": 0.50, "room_name": "Lab 3.02" },
    { "beacon_identifier": "1:3", "room_id": 4, "position_x": 0.00, "position_y": 0.90, "room_name": "Lab 3.03" }
  ]
}
```

Each entry gives the beacon's identifier (`"major:minor"`), its room, and its
`position_x` / `position_y` within that room (may be `null` if the beacon
hasn't been placed). Beacon coordinates follow the shared coordinate contract:
they are normalized to the room, 0–1 on both axes, with (0, 0) the top-left
corner and (1, 1) the bottom-right corner. Consumers (e.g. the admin radar)
clamp values outside 0–1 into range, and senders SHOULD normalize before
posting. Store this mapping in memory; the positions feed on-device
trilateration. Admins receive the same shape via `GET /api/v1/admin/beacons`
(which also includes `id` and `name`). Positions are set by admins through
`POST` / `PATCH /api/v1/admin/beacons` (`position_x` / `position_y`, both
optional and nullable). Re-fetch on app foreground if the mapping might have
changed (rare).

### Phase B (on every beacon detection while the app is running)

When Core Location's `CLBeaconRegion` fires a "range" callback, resolve the detected beacon to a `room_id` from your cache, then POST:

```bash
curl -X POST http://localhost:3000/api/v1/presence \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"room_id":3,"battery_level":78}'
```

Response: `204 No Content`.

**Optional fields:**
- `position_x`, `position_y` — if you compute a position estimate (e.g. from RSSI triangulation).
- `battery_level` — device battery percentage 0–100, useful for admin dashboards.

**Coordinate contract:** `position_x` / `position_y` are normalized to the
room, 0–1 on both axes — (0, 0) is the room's top-left corner and (1, 1) is
the bottom-right corner. Values outside that range are clamped by consumers
(such as the admin Live Radar), so senders SHOULD normalize their estimates
before posting.

**Rate limit:** 20 requests per learner per minute. The iPhone app should ping every ~5 minutes normally, so 20/min is a generous ceiling to prevent runaway loops.

### Swift sketch

```swift
struct PresenceBody: Encodable {
    let room_id: Int
    let position_x: Double?
    let position_y: Double?
    let battery_level: Int?
}

func reportPresence(roomId: Int, battery: Int?) async throws {
    let url = URL(string: "http://localhost:3000/api/v1/presence")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(tokenStore.accessToken)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONEncoder().encode(
        PresenceBody(room_id: roomId, position_x: nil, position_y: nil, battery_level: battery)
    )
    let (_, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 204 else {
        throw URLError(.badServerResponse)
    }
}
```

---

## Error handling

Every error response — regardless of endpoint or status code — has the same JSON shape:

```json
{
  "error": "invalid_credentials",
  "message": "Username or password is incorrect"
}
```

- `error` is a stable machine-readable code. Branch on this in your app.
- `message` is human-readable, may change wording between releases. Fine to display to the user if you don't have a custom translation.

The full error code list:

| Code | Status | When |
|---|---|---|
| `invalid_request` | 400 | Body malformed, missing fields, or fails schema (e.g. `battery_level: 200`). |
| `invalid_credentials` | 401 | Wrong username or password on login. |
| `invalid_grant` | 401 | Refresh token unknown, expired, or already used. |
| `unauthorized` | 401 | Missing or invalid access token. |
| `forbidden` | 403 | Authenticated but wrong role (e.g. learner hitting an admin endpoint). |
| `not_found` | 404 | Resource doesn't exist (e.g. room id). |
| `too_many_requests` | 429 | Rate limit exceeded. Retry after the `Retry-After` header. |
| `internal_error` | 500 | Server bug. Report it. |

### Swift decoding helper

```swift
struct ApiError: Decodable, Error {
    let error: String
    let message: String
}

func decodeApiError(_ data: Data) -> ApiError? {
    return try? JSONDecoder().decode(ApiError.self, from: data)
}
```

---

## Pagination

Endpoints that return lists (`/histories`, `/admin/overview`) support pagination:

```bash
curl "http://localhost:3000/api/v1/histories?page=2&per_page=50" \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

Response:

```json
{
  "list": [ ... ],
  "page": 2,
  "per_page": 50,
  "total": 137
}
```

- `page` — 1-indexed. Default 1.
- `per_page` — default 20, max 100.
- `total` — total row count across all pages.

Compute total pages as `Math.ceil(total / per_page)`.

---

## Field naming

- Every request and response field uses `snake_case` (e.g. `refresh_token`, `first_name`).
- Timestamps are ISO 8601 UTC (e.g. `"2026-07-03T08:14:22Z"`).
- Dates are `YYYY-MM-DD` and interpreted in the deployment timezone (configurable via `/api/v1/admin/system-config`).

In Swift, you can decode `snake_case` into `camelCase` by setting a decoder strategy:

```swift
let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
```

(All examples in this doc use `snake_case` field names verbatim for clarity; feel free to convert in the decoder.)

---

## Common gotchas

**"My token stopped working after 15 minutes."**
That's expected — access tokens expire fast. Call `/auth/refresh` to get a new pair. See [Step 3](#step-3--refresh-when-the-access-token-expires).

**"I sent the refresh token as `Authorization: Bearer` and got 401."**
Wrong token. The Bearer header wants the ACCESS token. Refresh tokens are only sent as the `refresh_token` field in `/auth/refresh` and `/auth/logout` bodies.

**"After I called refresh twice, everything returns 401."**
You reused a refresh token that was already rotated. This triggers the reuse-detection cascade — all your refresh tokens are revoked. User must log in again. Don't refresh from two threads simultaneously; serialize refreshes in your token store.

**"POST /presence returns 400 even with a valid room_id."**
Most likely you sent `room_id` as a string (`"3"`) instead of a number (`3`). Or you forgot `Content-Type: application/json`.

**"429 too_many_requests on login."**
Login rate limit is 5 failed attempts per (IP + username) per 15 minutes. Wait it out or use a different account.

**"Admin endpoint returns 403 for my admin user."**
Check the JWT you're sending — decode it at [jwt.io](https://jwt.io/) to confirm `role: "admin"`. Common cause: you're sending an old learner token from a previous test.

---

## Full endpoint list

Grouped for quick reference. For the full contract of each — request body, response shape, error codes — see [`api-reference.html`](api-reference.html).

**Auth (public):**
- `POST /auth/login`
- `POST /auth/refresh`
- `POST /auth/logout`

**Learner (`role: learner`):**
- `GET /api/v1/me`
- `GET /api/v1/dashboard`
- `GET /api/v1/histories?month=&year=&page=&per_page=`
- `POST /api/v1/presence`

**Any authenticated user:**
- `GET /api/v1/beacons`

**Admin (`role: admin`):**
- `GET /api/v1/admin/absence-summary`
- `GET /api/v1/admin/overview?name=&session=&page=&per_page=`
- `GET /api/v1/admin/rooms`
- `GET /api/v1/admin/rooms/:room_id/map`
- `GET /api/v1/admin/rooms/:room_id/current-occupants`
- `GET /api/v1/admin/rooms/:room_id/additional-data`
- `GET /api/v1/admin/session-config`
- `PUT /api/v1/admin/session-config/:session`
- `GET /api/v1/admin/system-config`
- `PUT /api/v1/admin/system-config`
- `POST /api/v1/admin/rollup`

---

## Where to look when stuck

1. **Check the backend logs.** In the terminal running `npm run dev`, every failed request logs why. `pino-pretty` is enabled in dev so the output is readable.
2. **Check `api-reference.html`.** It lists every field, constraint, and error code.
3. **Check the `.env`.** Wrong `JWT_SECRET` or DB creds cause silent 401s on all endpoints.
4. **Ping the backend developer.** Better to ask than guess.
