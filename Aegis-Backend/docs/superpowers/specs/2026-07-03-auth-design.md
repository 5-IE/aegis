# Aegis Backend — Authentication Design

**Date:** 2026-07-03
**Status:** Approved for implementation
**Scope:** Authentication only. Authorization endpoints (presence, attendance, admin) covered in a follow-up spec.

## Goal

Provide login, token refresh, and logout for two first-party native clients (iPhone learner app, macOS admin app) using plain JWT authentication. The Aegis backend is both authorization server and resource server.

## Why plain JWT, not OAuth2 PKCE

OAuth2 PKCE was considered and rejected. The threat model it defends against — malicious third-party apps scraping user credentials — does not exist in Aegis. Both clients are first-party and controlled by the same team as the backend. Plain JWT provides the same practical security posture (bcrypt passwords, short-lived access tokens, rotating refresh tokens, rate limiting) with roughly 40% less code and no browser-based login sheet. If a third-party client is ever required, PKCE can be layered on without breaking existing native clients.

## Endpoints

All under `/auth`. Request and response bodies are JSON.

### POST /auth/login

Public. Rate-limited.

Request:
```json
{ "username": "alice", "password": "hunter2" }
```

Response 200:
```json
{
  "access_token": "<jwt>",
  "refresh_token": "<opaque>",
  "expires_in": 900,
  "user": {
    "id": 42,
    "username": "alice",
    "role": "learner",
    "session": "AM",
    "first_name": "Alice",
    "last_name": "Doe",
    "email": "alice@example.com"
  }
}
```

Errors:
- 400 `invalid_request` — missing or malformed body
- 401 `invalid_credentials` — username not found or password mismatch
- 429 `too_many_requests` — rate limit exceeded

### POST /auth/refresh

Public. Rate-limited.

Request:
```json
{ "refresh_token": "<opaque>" }
```

Response 200:
```json
{
  "access_token": "<jwt>",
  "refresh_token": "<opaque>",
  "expires_in": 900
}
```

The presented refresh token is revoked and replaced. If the presented token has already been revoked, this is treated as reuse: all refresh tokens for that user are revoked and a 401 is returned. This detects stolen tokens.

Errors:
- 400 `invalid_request`
- 401 `invalid_grant` — token not found, expired, or reuse detected

### POST /auth/logout

Public. Idempotent.

Request:
```json
{ "refresh_token": "<opaque>" }
```

Response 204. Marks the refresh token revoked. Unknown or already-revoked tokens still return 204 (logout is idempotent). The paired access token continues to work until its 15-minute expiry — this is an accepted tradeoff.

## Tokens

### Access token

- JWT signed with HS256 using `JWT_SECRET` (env var, required at boot).
- Lifetime: 15 minutes.
- Claims:
  ```json
  {
    "sub": 42,
    "role": "learner",
    "session": "AM",
    "iat": 1751500000,
    "exp": 1751500900,
    "iss": "aegis"
  }
  ```
- `session` is included only for learners; omitted for admins.

### Refresh token

- 32 random bytes, base64url-encoded (~43 chars). Opaque to clients.
- Lifetime: 30 days from issue.
- Stored server-side as SHA256 hash. Plaintext is never persisted.
- Rotating: every use invalidates the old token and issues a new one.
- Reuse of a revoked token triggers a cascade revoke of all tokens for that user.

## Middleware

- **`requireAuth`** — extracts `Authorization: Bearer <jwt>`, verifies signature and `exp` with `JWT_SECRET`, attaches `req.user = { id, role, session }` from claims. Rejects 401 on any failure. No DB lookup.
- **`requireRole(role)`** — used after `requireAuth`. Returns 403 if `req.user.role !== role`.

Consumers (presence, attendance, admin endpoints) chain these in their route definitions. Those endpoints are out of scope for this spec.

## Schema changes

Two changes to `docs/aegis.sql`, delivered as migrations.

### Migration 0002 — bcrypt password column

```sql
ALTER TABLE `USER` MODIFY `password` VARCHAR(72) NOT NULL;
```

Comment in the column update reflects that the column now stores a bcrypt hash. No production data yet, so no backfill is needed.

### Migration 0003 — refresh token table

```sql
CREATE TABLE `REFRESH_TOKEN` (
  `id_token` INT AUTO_INCREMENT,
  `id_user` INT NOT NULL,
  `token_hash` CHAR(64) NOT NULL UNIQUE,
  `expires_at` TIMESTAMP NOT NULL,
  `revoked_at` TIMESTAMP NULL,
  `replaced_by_id` INT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id_token`),
  FOREIGN KEY (`id_user`) REFERENCES `USER`(`id_user`) ON DELETE CASCADE,
  FOREIGN KEY (`replaced_by_id`) REFERENCES `REFRESH_TOKEN`(`id_token`) ON DELETE SET NULL,
  INDEX `idx_user` (`id_user`),
  INDEX `idx_expires` (`expires_at`)
);
```

- `token_hash` is `CHAR(64)` because SHA256 in hex is exactly 64 chars.
- `replaced_by_id` links a rotated token to its successor, enabling reuse detection audits.
- `idx_expires` supports a periodic cleanup job (delete rows where `expires_at < NOW()`).

## Project layout

```
Aegis-Backend/
  src/
    routes/
      auth.ts               # login, refresh, logout handlers
    middleware/
      requireAuth.ts
      requireRole.ts
      rateLimit.ts
    services/
      authService.ts        # login logic, token issue/rotate/revoke
      passwordService.ts    # bcrypt hash/verify
      tokenService.ts       # JWT sign/verify, refresh token generate/hash
    db/
      pool.ts               # mysql2 pool
      queries/
        userQueries.ts
        refreshTokenQueries.ts
    lib/
      errors.ts             # typed error shapes
      logger.ts             # pino
    app.ts                  # express app assembly
    server.ts               # boot
  migrations/
    0001_init.sql           # from docs/aegis.sql
    0002_bcrypt_password.sql
    0003_refresh_token.sql
  scripts/
    seed.ts                 # first admin bootstrap
    migrate.ts              # apply migrations in order
  tests/
    auth/
      login.test.ts
      refresh.test.ts
      logout.test.ts
  docs/
  .env.example
  package.json
  tsconfig.json
```

## Dependencies

- `express` — HTTP
- `mysql2` — DB driver, promise API
- `bcrypt` — password hashing (cost factor 12)
- `jsonwebtoken` — JWT sign and verify
- `zod` — request body validation
- `express-rate-limit` — brute-force protection
- `pino` + `pino-pretty` — logging
- `dotenv` — env vars

Dev:
- `typescript`, `tsx`, `@types/*`
- `vitest`, `supertest`
- `eslint`, `prettier`

## Configuration

Required env vars (fail fast at boot if missing):

- `JWT_SECRET` — HS256 key, at least 32 bytes of entropy
- `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`
- `PORT` (default 3000)
- `LOG_LEVEL` (default `info`)

Seed script additionally requires:
- `SEED_ADMIN_USERNAME`
- `SEED_ADMIN_PASSWORD`
- `SEED_ADMIN_EMAIL`

## Rate limiting

Applied to `/auth/login` and `/auth/refresh`:

- `express-rate-limit` with in-memory store.
- Key: `${ip}:${body.username ?? ''}`.
- Window: 15 minutes.
- Max failures: 5.
- Successful requests do not count.
- Response on exceed: 429 with `Retry-After` header.

In-memory is acceptable because v1 targets single-instance deployment. Distributed rate limiting (Redis) is deferred.

## Error shape

All errors return:
```json
{ "error": "invalid_credentials", "message": "Username or password is incorrect" }
```

Error codes are stable and machine-readable. Messages are human-readable and may change. Codes used:

- `invalid_request` (400)
- `invalid_credentials` (401)
- `invalid_grant` (401)
- `unauthorized` (401)
- `forbidden` (403)
- `too_many_requests` (429)
- `internal_error` (500)

## Seed script

`scripts/seed.ts` reads `SEED_ADMIN_*` env vars, checks whether a user with that username exists, and inserts an admin row if not. Idempotent. Intended to be run once in each environment during initial setup.

## Testing

- Unit tests with Vitest.
- DB layer mocked at the query-function level (`userQueries`, `refreshTokenQueries`), so service and route logic is testable without a running MySQL.
- Auth service tests cover: successful login, wrong password, unknown user, refresh happy path, refresh with revoked token triggers cascade, logout idempotency, JWT expiry rejection.
- Route tests via `supertest` against the assembled Express app.

Integration tests against a real MySQL are deferred; documented as tech debt.

## Out of scope for v1

- Password reset (self-service and admin-triggered)
- Self-signup
- Email verification
- Anti-spoofing of presence pings (documented as a known limitation of the overall system, not just auth)
- Distributed rate limit store
- Instant access-token revocation (jti denylist)
- Multi-factor authentication
- OAuth2 or third-party client support

## Known limitations

- Access tokens cannot be revoked before their 15-minute expiry. Logout only revokes the refresh token. Mitigation: keep access token lifetime short.
- Rate limit is per-instance; a scale-out deployment would allow N× the configured attempts. Mitigation: single-instance for v1.
- Passwords are set only via seed script or (future) admin endpoint. No self-service in v1.
