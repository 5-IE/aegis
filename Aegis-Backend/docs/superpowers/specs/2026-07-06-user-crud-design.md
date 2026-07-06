# Aegis Backend — Admin User CRUD Design

**Date:** 2026-07-06
**Status:** Approved for implementation planning
**Scope:** 7 admin-only endpoints for user management, plus one migration adding a soft-delete column.
**Depends on:** [`2026-07-03-auth-design.md`](2026-07-03-auth-design.md) and [`2026-07-04-attendance-api-design.md`](2026-07-04-attendance-api-design.md).

## Goal

Give admins a full user-management surface via the API — list, view, create, update, reset password, soft-delete, and reactivate. Replace the current situation where users can only be created via the seed script and can never be modified.

## Non-goals for v1

- Self-service profile edits by learners (learners see their profile via `/api/v1/me` but cannot modify it)
- Password reset by the user themselves (only admins can reset another user's password)
- Email verification, password strength rules beyond bcrypt's 72-byte cap
- Bulk import/export of users
- Audit log of who changed what (any admin can act on any user; no per-action attribution stored beyond git-history-of-code discipline)

## Data model change

One migration adds a soft-delete column to `USER`.

### Migration 0006 — `is_active` column on USER

```sql
USE `AEGIS`;

ALTER TABLE `USER`
  ADD COLUMN `is_active` BOOLEAN NOT NULL DEFAULT TRUE;

CREATE INDEX `idx_user_active` ON `USER` (`is_active`);
```

Every existing row gets `is_active = TRUE`.

## Impact on existing queries

Existing user-facing queries must add `WHERE is_active = TRUE`:

| Query | Reason |
|---|---|
| `findUserByUsername` | Prevent inactive users from logging in (returns null → invalid_credentials) |
| `findUserById` | Prevent JWT-authenticated but soft-deleted users from doing anything (returns null → routes throw not_found or unauthorized) |
| `listLearners` | Hide inactive learners from admin overview |
| `listLearnerIds` | Same, plus stops the nightly rollup from producing new `ATTENDANCE_HISTORY` rows for inactive users |
| `countLearners` | Match `listLearners` scope |

**Not affected:** presence-derived queries (`firstAndLastPingBulk`, `currentRoomPerUser`) — those filter by user IDs already sourced from `listLearnerIds`. Attendance history for inactive users is preserved (historical audit trail).

The new user-management endpoints below have their own scoping logic — GET/PATCH/DELETE etc. bypass the `is_active` filter (see per-endpoint sections).

## Endpoint catalogue

All under `/api/v1/admin/users`. Every endpoint requires `requireAuth` + `requireRole('admin')`.

| # | Method | Path | Purpose |
|---|---|---|---|
| U1 | GET | `/admin/users` | Paged list of users (filter by role, session, name, active) |
| U2 | GET | `/admin/users/:id` | Get one user by id (returns regardless of active state) |
| U3 | POST | `/admin/users` | Create a new user |
| U4 | PATCH | `/admin/users/:id` | Partial update (excludes username, password, is_active) |
| U5 | PUT | `/admin/users/:id/password` | Reset password + revoke that user's refresh tokens |
| U6 | DELETE | `/admin/users/:id` | Soft delete (sets is_active = FALSE) + revoke refresh tokens |
| U7 | POST | `/admin/users/:id/reactivate` | Set is_active = TRUE |

## Endpoint details

### U1 — GET /api/v1/admin/users

**Auth:** admin.

**Query parameters:**

| Param | Type | Notes |
|---|---|---|
| `role?` | `admin \| learner` | Filter |
| `session?` | `AM \| PM` | Filter |
| `name?` | string, max 100 | Case-insensitive substring on `TRIM(CONCAT_WS(' ', first_name, last_name))` |
| `include_inactive?` | boolean | Default `false`. If true, returns active + inactive; else active-only |
| `page?` | integer | Default 1 |
| `per_page?` | integer | Default 20, max 100 |

**Ordering:** `first_name ASC, last_name ASC, id_user ASC` (id_user tiebreak for stable pagination when names are identical or null).

**Response 200:**

```json
{
  "list": [
    {
      "id": 42,
      "username": "alice",
      "email": "alice@example.com",
      "role": "learner",
      "session": "AM",
      "first_name": "Alice",
      "last_name": "Doe",
      "is_active": true,
      "created_at": "2026-01-15T00:00:00Z"
    }
  ],
  "page": 1,
  "per_page": 20,
  "total": 65
}
```

**Never includes `password` in any response.**

### U2 — GET /api/v1/admin/users/:id

**Auth:** admin.

Returns the user regardless of `is_active` state. Admin UI can render inactive users with a badge.

**Response 200:** single user object (same shape as one list item).

**Errors:** 404 `not_found`.

### U3 — POST /api/v1/admin/users

**Auth:** admin.

**Request body:**

```json
{
  "username": "alice",
  "password": "hunter2",
  "email": "alice@example.com",
  "role": "learner",
  "session": "AM",
  "first_name": "Alice",
  "last_name": "Doe"
}
```

**Validation (zod, `.strict()`):**

- `username`: string, 1–50 chars, must be unique across all users (including inactive)
- `password`: string, 1–72 chars (bcrypt limit)
- `email`: string, valid email format, ≤100 chars, must be unique across active users only (inactive users can hold an email address that a new user reuses — matches the intent that soft delete "frees" identifiers for reuse)
- `role`: `admin` or `learner`
- `session`: `AM` or `PM` — **required** when `role === 'learner'`; **ignored** when `role === 'admin'` (stored as DB default `AM` for admins; API responses omit `session` semantic meaning for admins as per the auth spec)
- `first_name`, `last_name`: optional, ≤50 chars each

**Behavior:**
1. Bcrypt the password (cost 12) via `passwordService.hashPassword`.
2. Insert row with `is_active = TRUE` (default).
3. Return the created user.

**Response 201:** the created user (same shape as U2 response, no password).

**Errors:**
- 400 `invalid_request` — schema failure, or `session` missing when `role === 'learner'`
- 409 `conflict` — `username` already exists (any state), or `email` already exists on an active user

### U4 — PATCH /api/v1/admin/users/:id

**Auth:** admin.

**Request body (all fields optional, `.strict()`):**

```json
{
  "email": "new@example.com",
  "first_name": "Alice",
  "last_name": "Smith",
  "session": "PM",
  "role": "admin"
}
```

**Validation:**

- Same field constraints as U3.
- `username`: **not allowed**. Delete + recreate if you must rename (protects the JWT `sub` semantic).
- `password`: **not allowed** here — use U5.
- `is_active`: **not allowed** here — use U6/U7.
- Uniqueness re-checked on `email` if it changes.
- If updating to `role: 'learner'`, `session` must be present in the same request (either from the existing row or in this patch).

**Behavior:**
1. Load current row (404 if missing, regardless of active state).
2. Build UPDATE with only present fields.
3. Return the updated user.

**Response 200:** the updated user.

**Errors:** 400, 404, 409.

### U5 — PUT /api/v1/admin/users/:id/password

**Auth:** admin.

**Request body (`.strict()`):**

```json
{ "new_password": "changeme" }
```

**Validation:** `new_password`: 1–72 chars.

**Behavior:**
1. 404 if user missing (regardless of active state).
2. Bcrypt-hash the password.
3. `UPDATE USER SET password = ? WHERE id_user = ?`.
4. Call `revokeAllRefreshTokensForUser(id)` — the target user's existing sessions are killed.
5. **Admin's own tokens are unaffected** (that middleware call is scoped to the target user only).

**Response:** 204 No Content.

**Errors:** 400, 404.

### U6 — DELETE /api/v1/admin/users/:id

**Auth:** admin. **Soft delete.**

**Behavior:**
1. 400 `invalid_request` — if `req.user.id === parseInt(:id)` (cannot delete yourself).
2. 404 if user missing.
3. If target's role is `admin`, check `SELECT COUNT(*) FROM USER WHERE role = 'admin' AND is_active = TRUE`. If count ≤ 1, return 400 `invalid_request` with message "Cannot delete the last active admin".
4. Otherwise: `UPDATE USER SET is_active = FALSE WHERE id_user = ?`.
5. Call `revokeAllRefreshTokensForUser(id)` — the deleted user is logged out everywhere.
6. Return 204.

**Response:** 204 No Content.

**Errors:**
- 400 `invalid_request` — self-delete or last-admin-delete
- 404 `not_found` — user missing

### U7 — POST /api/v1/admin/users/:id/reactivate

**Auth:** admin.

**Request body:** none (or `{}`).

**Behavior:**
1. 404 if user missing.
2. `UPDATE USER SET is_active = TRUE WHERE id_user = ?` (idempotent — no-op if already active).
3. Return 204.

**Response:** 204 No Content.

**Errors:** 404 `not_found`.

## Cross-cutting semantics

### Soft delete propagation

- **Login:** `findUserByUsername` filters `is_active = TRUE` → inactive users get `invalid_credentials` (same error as unknown user, prevents enumeration).
- **JWT already issued to now-inactive user:** their next request hits `requireAuth` → JWT verifies fine (signature valid, not expired) → route calls `findUserById` on a protected endpoint. If the endpoint reads the user row (e.g. `/me`, `/dashboard`), it gets null and throws `not_found` or `unauthorized`. The user is effectively locked out; access token dies within 15 minutes.
- **Refresh:** on soft delete we revoke all refresh tokens, so `/auth/refresh` immediately returns `invalid_grant`.
- **Nightly rollup:** `listLearnerIds` filters inactive → rollup only produces `ATTENDANCE_HISTORY` for active learners.
- **Admin views:** default active-only; `include_inactive=true` optional.

### Response shape consistency

Every user response uses this shape (no `password` ever):

```ts
{
  id: number;
  username: string;
  email: string;
  role: 'admin' | 'learner';
  session: 'AM' | 'PM';
  first_name: string | null;
  last_name: string | null;
  is_active: boolean;
  created_at: string;  // ISO 8601 UTC
}
```

`session` for admins is stored as the DB default (`AM`) and returned as-is; clients ignore it for admins per existing spec.

### Error codes

Reuses existing codes plus one addition:

- `invalid_request` (400)
- `unauthorized` (401)
- `forbidden` (403)
- `not_found` (404)
- **`conflict` (409)** — NEW; used only by U3/U4 for uniqueness violations

## Project layout additions

```
Aegis-Backend/
  src/
    routes/admin/
      users.ts                        # single router with all 7 endpoints
    services/
      userService.ts                  # NEW: create/update/delete/reactivate/reset-password logic
                                      # (existing authService handles login/refresh/logout)
    db/queries/
      userQueries.ts                  # MODIFY: add is_active filter to existing queries;
                                      # add updateUser, softDeleteUser, reactivateUser,
                                      # updateUserPassword, listUsers, countAdmins
  migrations/
    0006_user_is_active.sql           # NEW migration
  tests/
    routes/
      adminUsers.test.ts              # NEW route-level tests (supertest)
    services/
      userService.test.ts             # NEW service-level tests (queries mocked)
```

## Dependencies

No new runtime dependencies.

## Rate limits

No rate limit on these endpoints for v1 — admin surface is low-volume. Document as tech debt if abused.

## Config

No new config keys.

## Testing

- Unit tests: `userService` with mocked queries.
- Route tests: supertest against the assembled router, `userService` mocked.
- Coverage for every endpoint's happy path plus:
  - Login blocked when `is_active = FALSE`
  - Duplicate username → 409
  - Duplicate active email → 409
  - Duplicate email on inactive user → allowed (409-free)
  - Self-delete → 400
  - Last-admin delete → 400
  - Password reset revokes refresh tokens

Integration tests against a real MySQL still deferred; documented tech debt.

## Migration order

Applied by existing `scripts/migrate.ts`. New file sorts naturally after the attendance migrations:

```
0001_init.sql
0002_bcrypt_password.sql
0003_refresh_token.sql
0004_session_config.sql
0005_system_config.sql
0006_user_is_active.sql
```

## Known limitations

- Any admin can act on any user. No per-action audit log in v1 — git blame + backend logs cover the "who changed what" story for now.
- Soft-deleted users' `PRESENCE_LOG` and `ATTENDANCE_HISTORY` rows are retained. Data-retention policy is out of scope for v1.
- Reactivation restores the user with old email — if that email now belongs to a new active user, the reactivated user has a stale email. Admins reactivating are expected to check/update email in the same session.
- No email-verification round-trip on create or email change.

## Open follow-ups

- Add `updated_at` column on `USER` (currently only `created_at`). Small migration.
- Consider audit log table (`USER_AUDIT_LOG`) if regulatory needs emerge.
- Add rate limit on `POST /admin/users` and `PUT /admin/users/:id/password` if abuse appears.
