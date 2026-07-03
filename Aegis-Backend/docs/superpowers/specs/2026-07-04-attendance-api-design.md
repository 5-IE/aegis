# Aegis Backend — Attendance API Design

**Date:** 2026-07-04
**Status:** Approved for implementation planning
**Scope:** All non-auth application endpoints for v1 — 16 endpoints, 2 new config tables, 6 new services, 1 rollup script + admin trigger.
**Depends on:** [`2026-07-03-auth-design.md`](2026-07-03-auth-design.md) — auth subsystem must be in place first.

## Goal

Deliver the full read/write API surface behind the iPhone learner app and the macOS admin app for attendance tracking: presence ingestion, learner dashboard and history, admin dashboard and live-radar views, and admin-managed configuration of session windows + system knobs. Attendance history rolls up nightly from the raw presence log.

## Non-goals for v1

- Explicit user-triggered check-in / check-out actions (times are derived from `PRESENCE_LOG`)
- Leave request / approval flow (`leave` rows inserted manually or via seed)
- Real IoT sensor integration (`additional-data` endpoint returns mocked constants)
- Multi-timezone deployment (single `SYSTEM_CONFIG.timezone`)
- Real-time push (all endpoints polled)
- Back-fill of historical attendance for pre-existing data
- Anti-spoofing of presence pings (documented limitation)
- Multi-instance rollout (rate limiter and config cache are in-process)

## Data model changes

Two new tables plus their migrations. `USER`, `ROOM`, `DEVICE`, `PRESENCE_LOG`, `ATTENDANCE_HISTORY` are unchanged.

### Migration 0004 — `SESSION_CONFIG`

```sql
USE `AEGIS`;

CREATE TABLE `SESSION_CONFIG` (
  `session` ENUM('AM','PM') NOT NULL PRIMARY KEY,
  `start_time` TIME NOT NULL,
  `late_after` TIME NOT NULL,
  `end_time` TIME NOT NULL,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

INSERT INTO `SESSION_CONFIG` (`session`, `start_time`, `late_after`, `end_time`) VALUES
  ('AM', '08:00:00', '08:15:00', '12:00:00'),
  ('PM', '13:00:00', '13:15:00', '17:00:00');
```

Row-level invariant: `start_time < late_after < end_time`, enforced in the service layer on PUT.

AM/PM overlap between rows is permitted (admins may want lunch buffers). Documented as admin's responsibility.

### Migration 0005 — `SYSTEM_CONFIG`

```sql
USE `AEGIS`;

CREATE TABLE `SYSTEM_CONFIG` (
  `key` VARCHAR(64) NOT NULL PRIMARY KEY,
  `value` VARCHAR(255) NOT NULL,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

INSERT INTO `SYSTEM_CONFIG` (`key`, `value`) VALUES
  ('presence_staleness_minutes', '5'),
  ('timezone', 'Asia/Jakarta');
```

Only these two keys are recognized in v1. Unknown keys via PUT are rejected with `invalid_request`.

## Shared resources (response types)

Match the API HTML reference exactly:

```ts
interface RoomResource   { id: number; name: string }
interface UserResource   { id: number; name: string; session: 'AM' | 'PM' | null }  // name = first_name + " " + last_name; session=null for admins
interface LogResource    { id: number; user: UserResource; x: number | null; y: number | null }
```

`UserResource.name` is `first_name + " " + last_name`, trimmed. If either is null, the missing part is omitted; if both are null, `name` falls back to `username`.

## Endpoint catalogue

All under `/api/v1/`. Every endpoint requires a valid access token. Role is enforced via the middleware chain: `requireAuth` + `requireRole('learner' | 'admin')`.

### Learner (5 endpoints)

| # | Method | Path | Purpose |
|---|---|---|---|
| L1 | GET | `/me` | Return the authenticated learner's full profile |
| L2 | GET | `/dashboard` | Attendance counters + today_status |
| L3 | GET | `/histories` | Paged attendance history |
| L4 | POST | `/presence` | Record a beacon-detection ping |
| L5 | GET | `/beacons` | Beacon→room mapping for local caching |

### Admin (11 endpoints)

| # | Method | Path | Purpose |
|---|---|---|---|
| A1 | GET | `/admin/absence-summary` | Today's aggregate counters |
| A2 | GET | `/admin/overview` | Today's per-learner rows, filterable |
| A3 | GET | `/admin/rooms` | List of rooms |
| A4 | GET | `/admin/rooms/:id/map` | Latest per-user positions in one room |
| A5 | GET | `/admin/rooms/:id/current-occupants` | Users currently in one room with durations |
| A6 | GET | `/admin/rooms/:id/additional-data` | Environmental readings (mocked) |
| A7 | GET | `/admin/session-config` | Read AM+PM session windows |
| A8 | PUT | `/admin/session-config/:session` | Update one session's window |
| A9 | GET | `/admin/system-config` | Read staleness + timezone |
| A10 | PUT | `/admin/system-config` | Update staleness and/or timezone |
| A11 | POST | `/admin/rollup` | Manually trigger attendance rollup |

Grand total: 16 endpoints in this spec, plus the 3 auth endpoints already implemented.

## Endpoint details

### L1 — GET /me

**Auth:** learner. **Response 200:**

```json
{
  "id": 42,
  "first_name": "Alice",
  "last_name": "Doe",
  "username": "alice",
  "email": "alice@example.com",
  "role": "learner",
  "session": "AM"
}
```

`session` is `null` for admins, though this endpoint is learner-only so it will always be `"AM"` or `"PM"`.

### L2 — GET /dashboard

**Auth:** learner. **Response 200:**

```json
{
  "total_attendance": 92,
  "total_late": 7,
  "leave_taken": 3,
  "today_status": "Checked In"
}
```

- `total_attendance` = count of `ATTENDANCE_HISTORY` rows for this user with `status IN ('early','late')`
- `total_late` = count with `status = 'late'`
- `leave_taken` = count with `status = 'leave'`
- `today_status` — computed via `statusService.computeTodayStatus(user, now)`; see rules below

### L3 — GET /histories

**Auth:** learner. **Query params:**

- `month?` — integer 1–12; requires `year`
- `year?` — integer; may be given without `month`
- `page` — integer, default 1
- `per_page` — integer, default 20, max 100

**Ordering:** `date DESC` (most recent first).

**Response 200:**

```json
{
  "list": [
    { "date": "2026-07-01", "checked_in_at": "2026-07-01T08:04:12Z", "checked_out_at": "2026-07-01T11:58:41Z", "status": "early" },
    { "date": "2026-07-02", "checked_in_at": null, "checked_out_at": null, "status": "leave" }
  ],
  "page": 1,
  "per_page": 20,
  "total": 137
}
```

`checked_in_at` and `checked_out_at` are derived from `PRESENCE_LOG` (option A: first ping today = check-in; last ping today = check-out). For rows where no presence exists (leave, absent), both are `null`.

### L4 — POST /presence

**Auth:** learner. **Rate limit:** 20 requests / learner / minute (in-memory).

**Request body:**

```json
{
  "room_id": 3,
  "position_x": 4.2,
  "position_y": 7.1,
  "battery_level": 78
}
```

- `room_id` — integer, must exist in `ROOM`. Client resolves beacon→room via L5 before calling.
- `position_x`, `position_y` — floats, optional
- `battery_level` — integer 0–100, optional

**Behavior:**
1. Validate body.
2. Verify `room_id` exists (else 400 `invalid_request`).
3. Insert `PRESENCE_LOG(id_user=req.user.id, id_room, timestamp=NOW(), position_x, position_y, battery_level)`.
4. Return 204.

Accepts pings at any time (including weekends, outside session windows). Status derivation handles semantics.

**Response:** 204 No Content.

### L5 — GET /beacons

**Auth:** any authenticated user (learner or admin). **Response 200:**

```json
{
  "list": [
    { "beacon_identifier": "1:2", "room_id": 3, "room_name": "Lab 3.02" }
  ]
}
```

Excludes devices with `id_room IS NULL` (unassigned).

### A1 — GET /admin/absence-summary

**Auth:** admin. **Response 200:**

```json
{
  "present_summary": { "on_time": 54, "late_clock_in": 6 },
  "absent_summary": { "absent": 3, "no_clock_in": 2 }
}
```

Counts across all users where `role = 'learner'`, for today (local timezone from `SYSTEM_CONFIG.timezone`):

- `on_time` — learners with first ping today at or before their session's `late_after`
- `late_clock_in` — learners with first ping today after `late_after` but before `end_time`
- `absent` — learners with today's `ATTENDANCE_HISTORY` row set to `leave`, OR learners with no ping today AND whose session `end_time` has passed
- `no_clock_in` — learners with no ping today AND whose session `end_time` has NOT yet passed

`on_time + late_clock_in + absent + no_clock_in` equals total learner count.

### A2 — GET /admin/overview

**Auth:** admin.

**Query params:**

- `name?` — case-insensitive substring match on `TRIM(CONCAT_WS(' ', first_name, last_name))`
- `session?` — `"AM"` or `"PM"`
- `page` — integer, default 1
- `per_page` — integer, default 20, max 100

**Ordering:** `first_name ASC, last_name ASC`. Only `role = 'learner'` rows returned.

**Response 200:**

```json
{
  "list": [
    {
      "name": "Alice Doe",
      "session": "AM",
      "clocked_in_at": "2026-07-03T08:04:12Z",
      "clocked_out_at": null,
      "status": "Checked In"
    }
  ],
  "page": 1,
  "per_page": 20,
  "total": 65
}
```

`clocked_in_at` / `clocked_out_at` = first / last ping today (or null). `status` = same 6-value enum as learner dashboard.

### A3 — GET /admin/rooms

**Auth:** admin. **Response 200:**

```json
{ "list": [ { "id": 1, "name": "Lab 3.02" } ] }
```

Ordered by `id ASC`. No pagination — rooms are few.

### A4 — GET /admin/rooms/:id/map

**Auth:** admin. **Response 200:**

```json
{
  "list": [
    { "id": 10921, "user": { "id": 42, "name": "Alice Doe", "session": "AM" }, "x": 4.2, "y": 7.1 }
  ]
}
```

For each user whose **current room** (strongest-by-recency within staleness window) equals `:id`, return their most recent log in that room. A user physically pinged from Room A 3 minutes ago and Room B 2 minutes ago appears **only in Room B's map** — never in both.

Room 404 if `:id` not found.

### A5 — GET /admin/rooms/:id/current-occupants

**Auth:** admin. **Response 200:**

```json
{
  "list": [
    {
      "user": { "id": 42, "name": "Alice Doe", "session": "AM" },
      "duration_seconds": 4823,
      "status": "Checked In"
    }
  ]
}
```

Same "current room" rule as A4. `duration_seconds` = seconds since the user's **first ping today anywhere** (not since entering the current room). Room 404 if `:id` not found.

### A6 — GET /admin/rooms/:id/additional-data

**Auth:** admin. **Mocked** in v1. **Response 200:**

```json
{
  "room_temperature": 24.5,
  "humidity": 62,
  "people_in_room": 18
}
```

`room_temperature` and `humidity` are hardcoded constants. `people_in_room` = live count of current occupants (same calculation as A5). Room 404 if `:id` not found.

### A7 — GET /admin/session-config

**Auth:** admin. **Response 200:**

```json
{
  "AM": { "start_time": "08:00:00", "late_after": "08:15:00", "end_time": "12:00:00" },
  "PM": { "start_time": "13:00:00", "late_after": "13:15:00", "end_time": "17:00:00" }
}
```

### A8 — PUT /admin/session-config/:session

**Auth:** admin. `:session` is `"AM"` or `"PM"`.

**Request body:**

```json
{ "start_time": "08:00:00", "late_after": "08:15:00", "end_time": "12:00:00" }
```

All three fields required. Format `HH:MM:SS`, 24-hour. Validation: `start_time < late_after < end_time`. AM/PM cross-row overlap is allowed.

**Response:** 204. On success, invalidate the in-process `sessionConfig` cache immediately.

### A9 — GET /admin/system-config

**Auth:** admin. **Response 200:**

```json
{
  "presence_staleness_minutes": 5,
  "timezone": "Asia/Jakarta"
}
```

### A10 — PUT /admin/system-config

**Auth:** admin. **Partial update** — only fields present in the body are changed.

**Request body:**

```json
{ "presence_staleness_minutes": 5, "timezone": "Asia/Jakarta" }
```

- `presence_staleness_minutes` — integer 1..60
- `timezone` — IANA name, validated via `new Intl.DateTimeFormat('en-US', {timeZone: value})` (throws → 400)

**Response:** 204. On success, invalidate the in-process `systemConfig` cache immediately.

### A11 — POST /admin/rollup

**Auth:** admin. **Synchronous.** No rate limit.

**Request body (all fields optional):**

```json
{ "date": "2026-07-03", "user_id": 42 }
```

- `date` — `YYYY-MM-DD`; defaults to yesterday in `SYSTEM_CONFIG.timezone`
- `user_id` — integer; defaults to all learners

**Response 200:**

```json
{ "processed": 60, "skipped_leave": 2 }
```

- `processed` — rows inserted or updated
- `skipped_leave` — rows where an existing `leave` row was preserved

## Cross-cutting semantics

### Status derivation (used by L2, A1, A2)

Rules evaluated in order; the first matching rule wins. All time comparisons use `SYSTEM_CONFIG.timezone`. `session` = the learner's assigned session's config row.

1. If today's `ATTENDANCE_HISTORY.status = 'leave'` → **"Off"**
2. If **any** ping today AND `now < session.end_time` → **"Checked In"**
3. If **any** ping today AND `now >= session.end_time` AND last ping within `staleness_minutes` → **"Not Checked Out"**
4. If **any** ping today AND `now >= session.end_time` AND last ping older than `staleness_minutes` → **"Checked Out"**
5. If **no** ping today AND `now < session.late_after` → **"Not Checked In"**
6. If **no** ping today AND `session.late_after <= now < session.end_time` → **"Running Late"**
7. If **no** ping today AND `now >= session.end_time` → **"Not Checked In"** (session passed without appearance)

Every valid `(now, ping-existence)` pair matches exactly one rule.

### Historical status (used by nightly rollup, L3, A2 `status` fallback)

Four-value enum matching `ATTENDANCE_HISTORY.status`:

- `early` — first ping that day at or before `late_after`
- `late` — first ping that day after `late_after`
- `leave` — set only by manual insertion (admin/seed)
- `absent` — no ping that day and no existing `leave` row

### "Current room" rule (used by A4, A5, A6)

For each user with a ping within the last `staleness_minutes`, their current room is the room of their most recent ping. A user is in exactly one room at a time.

### Empty state handling

If there are 0 rooms, 0 learners, or 0 presence logs, every read endpoint returns 200 with an empty list or zeroed counters. Never 404 (except for `:id`-based paths where the specific resource doesn't exist).

### Timezone handling

- All `TIMESTAMP` values stored in DB are UTC.
- The service layer translates between `SYSTEM_CONFIG.timezone` local time and UTC using `Intl.DateTimeFormat` for boundary computation.
- SQL queries always use UTC bounds; no `CONVERT_TZ` in queries, no MySQL server TZ dependency.

## Nightly rollup

**Script:** `scripts/rollupAttendance.ts`, invoked via `npm run rollup [-- --date YYYY-MM-DD] [-- --user-id N]`.

**Behavior:**

1. Read `SYSTEM_CONFIG.timezone`. Determine the target date (default: yesterday in local TZ; else the `--date` arg).
2. Read `SESSION_CONFIG` for AM and PM windows.
3. For each learner (or the one from `--user-id`):
   - If a row already exists in `ATTENDANCE_HISTORY` for `(user, date)` with `status='leave'`, skip (increment `skipped_leave`).
   - Else compute the learner's first ping in their session's window on the target date.
   - Insert/upsert `ATTENDANCE_HISTORY(id_user, date, status)`:
     - Ping before `late_after` → `early`
     - Ping at/after `late_after` → `late`
     - No ping → `absent`
4. Log a summary line via pino.
5. Exit 0.

Uses `INSERT ... ON DUPLICATE KEY UPDATE status = VALUES(status)` for idempotency. Preserves manually-inserted `leave` rows via the skip check.

**Scheduling:** operator's cron at 03:00 local time. No in-process scheduler.

**Same code path** used by A11 (admin endpoint) and the CLI — the `rollupService.runRollup({date?, userId?})` function is the single implementation.

## Project layout (additions to auth layout)

```
Aegis-Backend/
  src/
    routes/
      me.ts
      dashboard.ts
      histories.ts
      presence.ts
      beacons.ts
      admin/
        absenceSummary.ts
        overview.ts
        rooms.ts
        sessionConfig.ts
        systemConfig.ts
        rollup.ts
    services/
      configService.ts          # session + system config, 30s TTL cache, invalidate on write
      statusService.ts          # today_status, historical status, current-room rules
      presenceService.ts        # ingestion (L4)
      dashboardService.ts       # L2 + A1
      overviewService.ts        # A2
      roomsService.ts           # A3, A4, A5, A6
      rollupService.ts          # rollup, used by CLI + A11
    db/
      queries/
        presenceQueries.ts
        roomQueries.ts
        deviceQueries.ts        # for L5 (beacons)
        attendanceHistoryQueries.ts
        sessionConfigQueries.ts
        systemConfigQueries.ts
    middleware/
      # requireAuth, requireRole already exist
  migrations/
    0004_session_config.sql
    0005_system_config.sql
  scripts/
    rollupAttendance.ts         # CLI wrapper around rollupService
  tests/
    routes/                     # new route tests
    services/                   # new service tests
```

## Dependencies

No new runtime dependencies. All standard-library JS + already-installed packages suffice (`Intl.DateTimeFormat` for timezone validation is built in).

## Rate limits

| Endpoint | Limit |
|---|---|
| POST `/api/v1/presence` | 20 requests / learner / minute |

All other application endpoints are unrate-limited in v1 (admin surface is low-volume; learner read endpoints don't need it). Auth-endpoint limits remain as documented in the auth spec.

## Error codes

Reuses codes defined in the auth spec: `invalid_request`, `unauthorized`, `forbidden`, `too_many_requests`, `internal_error`. Adds:

- `not_found` — HTTP 404, used for missing `:room_id`

## Config cache

- `configService` reads `SESSION_CONFIG` and `SYSTEM_CONFIG` once, caches for 30 seconds.
- On PUT (A8, A10), invalidate the affected cache immediately in the same process.
- Single-instance deployment for v1; a multi-instance rollout would need pub/sub or Redis.

## Testing

- Unit tests with Vitest, DB mocked at the `src/db/queries/*` seam.
- Service tests: `configService`, `statusService`, `presenceService`, `dashboardService`, `overviewService`, `roomsService`, `rollupService`.
- Route tests via `supertest`, mocking the service layer.
- CLI test: `scripts/rollupAttendance.ts` invocation mocked at `rollupService`.
- Integration tests against a real MySQL deferred; documented tech debt.

## Migration order

Applied by the existing `scripts/migrate.ts`. New files sort after auth migrations naturally:

```
0001_init.sql
0002_bcrypt_password.sql
0003_refresh_token.sql
0004_session_config.sql
0005_system_config.sql
```

## Known limitations

- All presence pings from any device claiming to be a given user are trusted (no anti-spoofing). Documented in auth spec.
- Rate limiter and config cache are per-instance. Scale-out multiplies limits.
- Rollup for a very large date range on many users could take a long time; A11 is synchronous with no timeout override. Document as tech debt.
- If timezone is changed and existing `PRESENCE_LOG` rows straddle the new day boundary, historical `today_status` and rollup results for that date could differ from prior queries. Rollup should be re-run for affected dates.
