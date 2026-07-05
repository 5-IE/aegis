# Aegis Attendance API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the full non-auth application surface for Aegis — 16 endpoints across learner (5) and admin (11), two new config tables, six new services, and a nightly rollup script.

**Architecture:** Same layering as auth — routes → services → queries. New services consume the auth middleware (`requireAuth`, `requireRole`). Timezone-aware "today" boundary logic lives in the service layer; SQL uses UTC bounds. Config values cached in-process for 30 s; invalidated immediately on PUT.

**Tech Stack:** Same as auth — Node.js 20+ / TypeScript strict / Express 4 / mysql2/promise / bcrypt / zod / express-rate-limit / pino / Vitest / supertest. No new runtime deps (`Intl.DateTimeFormat` for timezone validation is built in).

## Global Constraints

- TypeScript strict mode; ES modules (`"type": "module"`).
- DB access lives only in `src/db/*` — no `mysql2` imports elsewhere (except `scripts/*` boot scripts).
- Every route in this plan uses `requireAuth` chained with `requireRole('learner')` or `requireRole('admin')`.
- Every service ships with a unit test that mocks the DB query layer.
- Error response shape: `{ "error": "<code>", "message": "<human text>" }`.
- Error codes and status: `invalid_request` 400, `unauthorized` 401, `forbidden` 403, `not_found` 404, `too_many_requests` 429, `internal_error` 500.
- Response bodies use `snake_case`.
- All DB `TIMESTAMP` values are UTC. All local-day boundary math uses `SYSTEM_CONFIG.timezone` via `Intl.DateTimeFormat` in the service layer.
- Config cache: 30 s TTL, invalidated immediately on PUT (same process).
- Rate limit — presence: 20 requests / learner / minute (in-memory).
- Pagination defaults: `page=1`, `per_page=20`, `per_page` max 100.
- Session-config invariant: `start_time < late_after < end_time`; AM/PM cross-row overlap allowed.
- SystemConfig keys: only `presence_staleness_minutes` (int 1..60) and `timezone` (IANA); unknown keys rejected.
- Nightly rollup preserves existing `ATTENDANCE_HISTORY.status = 'leave'` rows.

---

## File Structure

**Created — migrations and scripts**
- `Aegis-Backend/migrations/0004_session_config.sql`
- `Aegis-Backend/migrations/0005_system_config.sql`
- `Aegis-Backend/scripts/rollupAttendance.ts`

**Created — DB queries**
- `Aegis-Backend/src/db/queries/sessionConfigQueries.ts`
- `Aegis-Backend/src/db/queries/systemConfigQueries.ts`
- `Aegis-Backend/src/db/queries/deviceQueries.ts`
- `Aegis-Backend/src/db/queries/roomQueries.ts`
- `Aegis-Backend/src/db/queries/presenceQueries.ts`
- `Aegis-Backend/src/db/queries/attendanceHistoryQueries.ts`

**Created — services**
- `Aegis-Backend/src/services/configService.ts`
- `Aegis-Backend/src/services/statusService.ts`
- `Aegis-Backend/src/services/presenceService.ts`
- `Aegis-Backend/src/services/dashboardService.ts`
- `Aegis-Backend/src/services/overviewService.ts`
- `Aegis-Backend/src/services/roomsService.ts`
- `Aegis-Backend/src/services/rollupService.ts`

**Created — routes**
- `Aegis-Backend/src/routes/me.ts`
- `Aegis-Backend/src/routes/dashboard.ts`
- `Aegis-Backend/src/routes/histories.ts`
- `Aegis-Backend/src/routes/presence.ts`
- `Aegis-Backend/src/routes/beacons.ts`
- `Aegis-Backend/src/routes/admin/absenceSummary.ts`
- `Aegis-Backend/src/routes/admin/overview.ts`
- `Aegis-Backend/src/routes/admin/rooms.ts`
- `Aegis-Backend/src/routes/admin/sessionConfig.ts`
- `Aegis-Backend/src/routes/admin/systemConfig.ts`
- `Aegis-Backend/src/routes/admin/rollup.ts`

**Created — middleware**
- `Aegis-Backend/src/middleware/presenceRateLimit.ts`

**Modified**
- `Aegis-Backend/src/lib/errors.ts` — add `not_found` error code
- `Aegis-Backend/src/app.ts` — mount new routers
- `Aegis-Backend/package.json` — add `rollup` script

**Not touched by this plan** — auth files (`src/services/authService.ts`, `src/routes/auth.ts`, `src/middleware/require*.ts`, etc.) already exist and are consumed as-is.

---

## Task 1: Migrations + query files for config tables

**Files:**
- Create: `Aegis-Backend/migrations/0004_session_config.sql`
- Create: `Aegis-Backend/migrations/0005_system_config.sql`
- Create: `Aegis-Backend/src/db/queries/sessionConfigQueries.ts`
- Create: `Aegis-Backend/src/db/queries/systemConfigQueries.ts`

**Interfaces:**
- Consumes: `pool` from `src/db/pool.ts` (auth)
- Produces:
  - `interface SessionConfigRow { session: 'AM' | 'PM'; start_time: string; late_after: string; end_time: string; updated_at: Date }` from `sessionConfigQueries.ts`
  - `async function getAllSessionConfigs(): Promise<SessionConfigRow[]>`
  - `async function getSessionConfig(session: 'AM' | 'PM'): Promise<SessionConfigRow | null>`
  - `async function updateSessionConfig(session: 'AM' | 'PM', input: { start_time: string; late_after: string; end_time: string }): Promise<void>`
  - `interface SystemConfigRow { key: string; value: string; updated_at: Date }` from `systemConfigQueries.ts`
  - `async function getAllSystemConfig(): Promise<SystemConfigRow[]>`
  - `async function upsertSystemConfig(key: string, value: string): Promise<void>`

- [ ] **Step 1: Create `Aegis-Backend/migrations/0004_session_config.sql`**

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

- [ ] **Step 2: Create `Aegis-Backend/migrations/0005_system_config.sql`**

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

- [ ] **Step 3: Create `Aegis-Backend/src/db/queries/sessionConfigQueries.ts`**

```ts
import { RowDataPacket } from 'mysql2';
import { pool } from '../pool.js';

export interface SessionConfigRow {
  session: 'AM' | 'PM';
  start_time: string;
  late_after: string;
  end_time: string;
  updated_at: Date;
}

export async function getAllSessionConfigs(): Promise<SessionConfigRow[]> {
  const [rows] = await pool.query<(SessionConfigRow & RowDataPacket)[]>(
    'SELECT `session`, `start_time`, `late_after`, `end_time`, `updated_at` FROM `SESSION_CONFIG` ORDER BY `session`',
  );
  return rows;
}

export async function getSessionConfig(session: 'AM' | 'PM'): Promise<SessionConfigRow | null> {
  const [rows] = await pool.query<(SessionConfigRow & RowDataPacket)[]>(
    'SELECT `session`, `start_time`, `late_after`, `end_time`, `updated_at` FROM `SESSION_CONFIG` WHERE `session` = ? LIMIT 1',
    [session],
  );
  return rows[0] ?? null;
}

export async function updateSessionConfig(
  session: 'AM' | 'PM',
  input: { start_time: string; late_after: string; end_time: string },
): Promise<void> {
  await pool.query(
    'UPDATE `SESSION_CONFIG` SET `start_time` = ?, `late_after` = ?, `end_time` = ? WHERE `session` = ?',
    [input.start_time, input.late_after, input.end_time, session],
  );
}
```

- [ ] **Step 4: Create `Aegis-Backend/src/db/queries/systemConfigQueries.ts`**

```ts
import { RowDataPacket } from 'mysql2';
import { pool } from '../pool.js';

export interface SystemConfigRow {
  key: string;
  value: string;
  updated_at: Date;
}

export async function getAllSystemConfig(): Promise<SystemConfigRow[]> {
  const [rows] = await pool.query<(SystemConfigRow & RowDataPacket)[]>(
    'SELECT `key`, `value`, `updated_at` FROM `SYSTEM_CONFIG`',
  );
  return rows;
}

export async function upsertSystemConfig(key: string, value: string): Promise<void> {
  await pool.query(
    'INSERT INTO `SYSTEM_CONFIG` (`key`, `value`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)',
    [key, value],
  );
}
```

- [ ] **Step 5: Type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add Aegis-Backend/migrations/0004_session_config.sql Aegis-Backend/migrations/0005_system_config.sql Aegis-Backend/src/db/queries/sessionConfigQueries.ts Aegis-Backend/src/db/queries/systemConfigQueries.ts
git commit -m "feat(db): add session_config and system_config tables and queries"
```

---

## Task 2: Add `not_found` error code

**Files:**
- Modify: `Aegis-Backend/src/lib/errors.ts`

**Interfaces:**
- Consumes: existing `AppError`, `ErrorCode`
- Produces: `AppError` now accepts `'not_found'` code with status 404 and default message

- [ ] **Step 1: Read the current file to locate the union and maps**

Run: `cat Aegis-Backend/src/lib/errors.ts`

- [ ] **Step 2: Add `'not_found'` to the `ErrorCode` union**

In `src/lib/errors.ts`, change:

```ts
export type ErrorCode =
  | 'invalid_request'
  | 'invalid_credentials'
  | 'invalid_grant'
  | 'unauthorized'
  | 'forbidden'
  | 'too_many_requests'
  | 'internal_error';
```

to:

```ts
export type ErrorCode =
  | 'invalid_request'
  | 'invalid_credentials'
  | 'invalid_grant'
  | 'unauthorized'
  | 'forbidden'
  | 'not_found'
  | 'too_many_requests'
  | 'internal_error';
```

- [ ] **Step 3: Add `'not_found'` to the STATUS map**

Change:

```ts
const STATUS: Record<ErrorCode, number> = {
  invalid_request: 400,
  invalid_credentials: 401,
  invalid_grant: 401,
  unauthorized: 401,
  forbidden: 403,
  too_many_requests: 429,
  internal_error: 500,
};
```

to:

```ts
const STATUS: Record<ErrorCode, number> = {
  invalid_request: 400,
  invalid_credentials: 401,
  invalid_grant: 401,
  unauthorized: 401,
  forbidden: 403,
  not_found: 404,
  too_many_requests: 429,
  internal_error: 500,
};
```

- [ ] **Step 4: Add `'not_found'` to DEFAULT_MESSAGE**

Change:

```ts
const DEFAULT_MESSAGE: Record<ErrorCode, string> = {
  invalid_request: 'The request is malformed or missing required fields',
  invalid_credentials: 'Username or password is incorrect',
  invalid_grant: 'The refresh token is invalid, expired, or already used',
  unauthorized: 'Authentication is required',
  forbidden: 'You do not have permission to access this resource',
  too_many_requests: 'Too many requests — please try again later',
  internal_error: 'An unexpected error occurred',
};
```

to:

```ts
const DEFAULT_MESSAGE: Record<ErrorCode, string> = {
  invalid_request: 'The request is malformed or missing required fields',
  invalid_credentials: 'Username or password is incorrect',
  invalid_grant: 'The refresh token is invalid, expired, or already used',
  unauthorized: 'Authentication is required',
  forbidden: 'You do not have permission to access this resource',
  not_found: 'The requested resource does not exist',
  too_many_requests: 'Too many requests — please try again later',
  internal_error: 'An unexpected error occurred',
};
```

- [ ] **Step 5: Full test suite (verify no regression)**

Run: `cd Aegis-Backend && npm test`
Expected: 32/32 pass (auth suite still green).

- [ ] **Step 6: Type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
git add Aegis-Backend/src/lib/errors.ts
git commit -m "feat(errors): add not_found error code (404)"
```

---

## Task 3: configService (cache + validation)

**Files:**
- Create: `Aegis-Backend/src/services/configService.ts`
- Create: `Aegis-Backend/tests/services/configService.test.ts`

**Interfaces:**
- Consumes: query functions from Task 1; `AppError` from `errors.ts`
- Produces:
  - `interface SessionConfig { session: 'AM' | 'PM'; start_time: string; late_after: string; end_time: string }`
  - `interface SystemConfig { presence_staleness_minutes: number; timezone: string }`
  - `async function getSessionConfigs(): Promise<{ AM: SessionConfig; PM: SessionConfig }>`
  - `async function getSystemConfig(): Promise<SystemConfig>`
  - `async function updateSessionConfig(session: 'AM' | 'PM', input: { start_time: string; late_after: string; end_time: string }): Promise<void>` — validates ordering, throws `AppError('invalid_request')`, invalidates cache
  - `async function updateSystemConfig(patch: { presence_staleness_minutes?: number; timezone?: string }): Promise<void>` — validates values, throws `AppError('invalid_request')`, invalidates cache
  - `function invalidateConfigCache(): void`

Cache impl: two module-level `let cached: T | null` variables with `cachedAt: number`. TTL 30 s. `invalidateConfigCache` clears both.

- [ ] **Step 1: Write failing test `tests/services/configService.test.ts`**

```ts
import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

vi.mock('../../src/db/queries/sessionConfigQueries.js', () => ({
  getAllSessionConfigs: vi.fn(),
  getSessionConfig: vi.fn(),
  updateSessionConfig: vi.fn(),
}));

vi.mock('../../src/db/queries/systemConfigQueries.js', () => ({
  getAllSystemConfig: vi.fn(),
  upsertSystemConfig: vi.fn(),
}));

const load = async () => {
  const svc = await import('../../src/services/configService.js');
  const sc = await import('../../src/db/queries/sessionConfigQueries.js');
  const sy = await import('../../src/db/queries/systemConfigQueries.js');
  return { svc, sc, sy };
};

beforeEach(() => vi.clearAllMocks());

describe('getSessionConfigs', () => {
  it('returns AM and PM configs', async () => {
    const { svc, sc } = await load();
    svc.invalidateConfigCache();
    (sc.getAllSessionConfigs as any).mockResolvedValue([
      { session: 'AM', start_time: '08:00:00', late_after: '08:15:00', end_time: '12:00:00', updated_at: new Date() },
      { session: 'PM', start_time: '13:00:00', late_after: '13:15:00', end_time: '17:00:00', updated_at: new Date() },
    ]);
    const r = await svc.getSessionConfigs();
    expect(r.AM.start_time).toBe('08:00:00');
    expect(r.PM.end_time).toBe('17:00:00');
  });
});

describe('getSystemConfig', () => {
  it('parses values by key', async () => {
    const { svc, sy } = await load();
    svc.invalidateConfigCache();
    (sy.getAllSystemConfig as any).mockResolvedValue([
      { key: 'presence_staleness_minutes', value: '7', updated_at: new Date() },
      { key: 'timezone', value: 'Asia/Jakarta', updated_at: new Date() },
    ]);
    const r = await svc.getSystemConfig();
    expect(r.presence_staleness_minutes).toBe(7);
    expect(r.timezone).toBe('Asia/Jakarta');
  });
});

describe('updateSessionConfig', () => {
  it('rejects if start_time >= late_after', async () => {
    const { svc } = await load();
    await expect(svc.updateSessionConfig('AM', { start_time: '08:15:00', late_after: '08:15:00', end_time: '12:00:00' }))
      .rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('rejects if late_after >= end_time', async () => {
    const { svc } = await load();
    await expect(svc.updateSessionConfig('AM', { start_time: '08:00:00', late_after: '12:00:00', end_time: '12:00:00' }))
      .rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('writes and invalidates cache on success', async () => {
    const { svc, sc } = await load();
    await svc.updateSessionConfig('AM', { start_time: '08:00:00', late_after: '08:15:00', end_time: '12:00:00' });
    expect(sc.updateSessionConfig).toHaveBeenCalledWith('AM', {
      start_time: '08:00:00', late_after: '08:15:00', end_time: '12:00:00',
    });
  });
});

describe('updateSystemConfig', () => {
  it('rejects out-of-range presence_staleness_minutes', async () => {
    const { svc } = await load();
    await expect(svc.updateSystemConfig({ presence_staleness_minutes: 0 })).rejects.toMatchObject({ code: 'invalid_request' });
    await expect(svc.updateSystemConfig({ presence_staleness_minutes: 61 })).rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('rejects invalid timezone', async () => {
    const { svc } = await load();
    await expect(svc.updateSystemConfig({ timezone: 'Not/A_Zone' })).rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('writes each present field', async () => {
    const { svc, sy } = await load();
    await svc.updateSystemConfig({ presence_staleness_minutes: 10, timezone: 'Asia/Jakarta' });
    expect(sy.upsertSystemConfig).toHaveBeenCalledWith('presence_staleness_minutes', '10');
    expect(sy.upsertSystemConfig).toHaveBeenCalledWith('timezone', 'Asia/Jakarta');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/services/configService.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Create `src/services/configService.ts`**

```ts
import { AppError } from '../lib/errors.js';
import {
  getAllSessionConfigs,
  updateSessionConfig as dbUpdateSessionConfig,
} from '../db/queries/sessionConfigQueries.js';
import {
  getAllSystemConfig,
  upsertSystemConfig,
} from '../db/queries/systemConfigQueries.js';

export interface SessionConfig {
  session: 'AM' | 'PM';
  start_time: string;
  late_after: string;
  end_time: string;
}

export interface SystemConfig {
  presence_staleness_minutes: number;
  timezone: string;
}

const TTL_MS = 30_000;

let sessionCache: { AM: SessionConfig; PM: SessionConfig } | null = null;
let sessionCachedAt = 0;
let systemCache: SystemConfig | null = null;
let systemCachedAt = 0;

export function invalidateConfigCache(): void {
  sessionCache = null;
  sessionCachedAt = 0;
  systemCache = null;
  systemCachedAt = 0;
}

function timeStrToSeconds(t: string): number {
  const [h, m, s] = t.split(':').map((x) => Number.parseInt(x, 10));
  return h * 3600 + m * 60 + s;
}

function isValidTimezone(tz: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

export async function getSessionConfigs(): Promise<{ AM: SessionConfig; PM: SessionConfig }> {
  const now = Date.now();
  if (sessionCache && now - sessionCachedAt < TTL_MS) return sessionCache;
  const rows = await getAllSessionConfigs();
  const AM = rows.find((r) => r.session === 'AM');
  const PM = rows.find((r) => r.session === 'PM');
  if (!AM || !PM) throw new AppError('internal_error', 'Session config missing rows');
  sessionCache = {
    AM: { session: 'AM', start_time: AM.start_time, late_after: AM.late_after, end_time: AM.end_time },
    PM: { session: 'PM', start_time: PM.start_time, late_after: PM.late_after, end_time: PM.end_time },
  };
  sessionCachedAt = now;
  return sessionCache;
}

export async function getSystemConfig(): Promise<SystemConfig> {
  const now = Date.now();
  if (systemCache && now - systemCachedAt < TTL_MS) return systemCache;
  const rows = await getAllSystemConfig();
  const map = new Map(rows.map((r) => [r.key, r.value] as const));
  const staleness = Number.parseInt(map.get('presence_staleness_minutes') ?? '5', 10);
  const timezone = map.get('timezone') ?? 'UTC';
  systemCache = { presence_staleness_minutes: staleness, timezone };
  systemCachedAt = now;
  return systemCache;
}

export async function updateSessionConfig(
  session: 'AM' | 'PM',
  input: { start_time: string; late_after: string; end_time: string },
): Promise<void> {
  const s = timeStrToSeconds(input.start_time);
  const l = timeStrToSeconds(input.late_after);
  const e = timeStrToSeconds(input.end_time);
  if (!(s < l && l < e)) {
    throw new AppError('invalid_request', 'Require start_time < late_after < end_time');
  }
  await dbUpdateSessionConfig(session, input);
  invalidateConfigCache();
}

export async function updateSystemConfig(patch: {
  presence_staleness_minutes?: number;
  timezone?: string;
}): Promise<void> {
  if (patch.presence_staleness_minutes !== undefined) {
    const v = patch.presence_staleness_minutes;
    if (!Number.isInteger(v) || v < 1 || v > 60) {
      throw new AppError('invalid_request', 'presence_staleness_minutes must be an integer 1..60');
    }
    await upsertSystemConfig('presence_staleness_minutes', String(v));
  }
  if (patch.timezone !== undefined) {
    if (!isValidTimezone(patch.timezone)) {
      throw new AppError('invalid_request', 'Unknown IANA timezone');
    }
    await upsertSystemConfig('timezone', patch.timezone);
  }
  invalidateConfigCache();
}
```

- [ ] **Step 4: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/services/configService.test.ts`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add Aegis-Backend/src/services/configService.ts Aegis-Backend/tests/services/configService.test.ts
git commit -m "feat(config): add configService with 30s cache and validation"
```

---

## Task 4: statusService — timezone-aware today + status derivation

**Files:**
- Create: `Aegis-Backend/src/services/statusService.ts`
- Create: `Aegis-Backend/tests/services/statusService.test.ts`

**Interfaces:**
- Consumes: `getSessionConfigs`, `getSystemConfig` from `configService`; presence queries from Task 5 (defined below — this task and Task 5 have interdependent tests; TDD constraint: this task's tests mock the presence query calls)
- Produces:
  - `type TodayStatus = 'Not Checked In' | 'Running Late' | 'Checked In' | 'Checked Out' | 'Not Checked Out' | 'Off'`
  - `type HistoricalStatus = 'early' | 'late' | 'leave' | 'absent'`
  - `function localDayBoundsUtc(now: Date, tz: string): { startUtc: Date; endUtc: Date }` — the UTC ms window that maps to `[00:00, 24:00)` local time on the local date containing `now`
  - `function localDateStr(now: Date, tz: string): string` — `YYYY-MM-DD` in local tz
  - `function combineLocalDateAndTime(localDate: string, timeHHMMSS: string, tz: string): Date` — the UTC Date corresponding to `<localDate>T<time>` in `tz`
  - `async function computeTodayStatus(userSession: 'AM' | 'PM', now: Date, firstPing: Date | null, lastPing: Date | null, hasLeave: boolean): Promise<TodayStatus>` — pure given config; consumes `configService`
  - `function computeHistoricalStatus(firstPing: Date | null, sessionLateAfterUtc: Date, existingLeave: boolean): HistoricalStatus`

- [ ] **Step 1: Write failing test `tests/services/statusService.test.ts`**

```ts
import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

vi.mock('../../src/services/configService.js', () => ({
  getSessionConfigs: vi.fn(),
  getSystemConfig: vi.fn(),
}));

const load = async () => {
  const svc = await import('../../src/services/statusService.js');
  const cfg = await import('../../src/services/configService.js');
  return { svc, cfg };
};

const AM = { session: 'AM' as const, start_time: '08:00:00', late_after: '08:15:00', end_time: '12:00:00' };
const PM = { session: 'PM' as const, start_time: '13:00:00', late_after: '13:15:00', end_time: '17:00:00' };

beforeEach(() => vi.clearAllMocks());

describe('localDayBoundsUtc', () => {
  it('produces a 24h window starting at local midnight', async () => {
    const { svc } = await load();
    // 2026-07-03 in Asia/Jakarta = UTC+7, so local midnight is 2026-07-02T17:00:00Z
    const now = new Date('2026-07-03T05:00:00Z'); // 12:00 local
    const { startUtc, endUtc } = svc.localDayBoundsUtc(now, 'Asia/Jakarta');
    expect(startUtc.toISOString()).toBe('2026-07-02T17:00:00.000Z');
    expect(endUtc.toISOString()).toBe('2026-07-03T17:00:00.000Z');
  });
});

describe('localDateStr', () => {
  it('formats the local date', async () => {
    const { svc } = await load();
    expect(svc.localDateStr(new Date('2026-07-03T05:00:00Z'), 'Asia/Jakarta')).toBe('2026-07-03');
  });
});

describe('combineLocalDateAndTime', () => {
  it('yields the UTC instant of a local wall-clock time', async () => {
    const { svc } = await load();
    // 2026-07-03T08:00 local +07:00 = 2026-07-03T01:00Z
    expect(svc.combineLocalDateAndTime('2026-07-03', '08:00:00', 'Asia/Jakarta').toISOString())
      .toBe('2026-07-03T01:00:00.000Z');
  });
});

describe('computeTodayStatus', () => {
  const setup = async (nowIso: string, opts?: Partial<{ session: 'AM' | 'PM'; firstIso: string; lastIso: string; leave: boolean }>) => {
    const { svc, cfg } = await load();
    (cfg.getSessionConfigs as any).mockResolvedValue({ AM, PM });
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' });
    const now = new Date(nowIso);
    const first = opts?.firstIso ? new Date(opts.firstIso) : null;
    const last = opts?.lastIso ? new Date(opts.lastIso) : first;
    return svc.computeTodayStatus(opts?.session ?? 'AM', now, first, last, opts?.leave ?? false);
  };

  it('returns Off on leave', async () => {
    expect(await setup('2026-07-03T05:00:00Z', { leave: true })).toBe('Off');
  });

  it('returns Checked In when pinged and session not ended', async () => {
    // now = 09:00 local, first ping 08:10 local
    expect(await setup('2026-07-03T02:00:00Z', { firstIso: '2026-07-03T01:10:00Z' })).toBe('Checked In');
  });

  it('returns Not Checked Out after end_time with fresh ping', async () => {
    // now = 12:03 local (past 12:00 end), last ping 12:00 local (3 min ago, within 5 min staleness)
    expect(await setup('2026-07-03T05:03:00Z', { firstIso: '2026-07-03T01:10:00Z', lastIso: '2026-07-03T05:00:00Z' })).toBe('Not Checked Out');
  });

  it('returns Checked Out after end_time when last ping is stale', async () => {
    // now = 12:30 local, last ping 11:00 local (90 min ago)
    expect(await setup('2026-07-03T05:30:00Z', { firstIso: '2026-07-03T01:10:00Z', lastIso: '2026-07-03T04:00:00Z' })).toBe('Checked Out');
  });

  it('returns Not Checked In before late_after with no ping', async () => {
    // now = 08:10 local, no ping, late_after 08:15
    expect(await setup('2026-07-03T01:10:00Z')).toBe('Not Checked In');
  });

  it('returns Running Late between late_after and end_time with no ping', async () => {
    // now = 09:00 local, no ping
    expect(await setup('2026-07-03T02:00:00Z')).toBe('Running Late');
  });

  it('returns Not Checked In after end_time with no ping', async () => {
    // now = 13:00 local, no ping, AM end_time 12:00
    expect(await setup('2026-07-03T06:00:00Z')).toBe('Not Checked In');
  });
});

describe('computeHistoricalStatus', () => {
  it('early when first ping before late_after', async () => {
    const { svc } = await load();
    expect(svc.computeHistoricalStatus(new Date('2026-07-03T01:10:00Z'), new Date('2026-07-03T01:15:00Z'), false)).toBe('early');
  });

  it('late when first ping at/after late_after', async () => {
    const { svc } = await load();
    expect(svc.computeHistoricalStatus(new Date('2026-07-03T01:20:00Z'), new Date('2026-07-03T01:15:00Z'), false)).toBe('late');
  });

  it('leave when existingLeave', async () => {
    const { svc } = await load();
    expect(svc.computeHistoricalStatus(null, new Date('2026-07-03T01:15:00Z'), true)).toBe('leave');
  });

  it('absent when no ping and no leave', async () => {
    const { svc } = await load();
    expect(svc.computeHistoricalStatus(null, new Date('2026-07-03T01:15:00Z'), false)).toBe('absent');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/services/statusService.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Create `src/services/statusService.ts`**

```ts
import { getSessionConfigs, getSystemConfig } from './configService.js';

export type TodayStatus =
  | 'Not Checked In'
  | 'Running Late'
  | 'Checked In'
  | 'Checked Out'
  | 'Not Checked Out'
  | 'Off';

export type HistoricalStatus = 'early' | 'late' | 'leave' | 'absent';

function parts(date: Date, tz: string): { y: number; m: number; d: number; h: number; mi: number; s: number } {
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
  });
  const out: Record<string, string> = {};
  for (const p of fmt.formatToParts(date)) {
    if (p.type !== 'literal') out[p.type] = p.value;
  }
  return {
    y: Number.parseInt(out.year, 10),
    m: Number.parseInt(out.month, 10),
    d: Number.parseInt(out.day, 10),
    h: Number.parseInt(out.hour === '24' ? '0' : out.hour, 10),
    mi: Number.parseInt(out.minute, 10),
    s: Number.parseInt(out.second, 10),
  };
}

// Return the UTC Date corresponding to <localDate>T<time> in tz.
export function combineLocalDateAndTime(localDate: string, timeHHMMSS: string, tz: string): Date {
  const [y, mo, d] = localDate.split('-').map((x) => Number.parseInt(x, 10));
  const [h, mi, s] = timeHHMMSS.split(':').map((x) => Number.parseInt(x, 10));

  // Iterative search: pick a guess, compute what local components that guess produces,
  // then adjust by the difference. tz offsets are integer minutes so this converges in 2 iterations.
  let guess = Date.UTC(y, mo - 1, d, h, mi, s);
  for (let i = 0; i < 3; i++) {
    const p = parts(new Date(guess), tz);
    const target = Date.UTC(y, mo - 1, d, h, mi, s);
    const actual = Date.UTC(p.y, p.m - 1, p.d, p.h, p.mi, p.s);
    const diff = target - actual;
    if (diff === 0) break;
    guess += diff;
  }
  return new Date(guess);
}

export function localDateStr(now: Date, tz: string): string {
  const p = parts(now, tz);
  const mm = String(p.m).padStart(2, '0');
  const dd = String(p.d).padStart(2, '0');
  return `${p.y}-${mm}-${dd}`;
}

export function localDayBoundsUtc(now: Date, tz: string): { startUtc: Date; endUtc: Date } {
  const date = localDateStr(now, tz);
  const startUtc = combineLocalDateAndTime(date, '00:00:00', tz);
  const endUtc = new Date(startUtc.getTime() + 24 * 60 * 60 * 1000);
  return { startUtc, endUtc };
}

export async function computeTodayStatus(
  userSession: 'AM' | 'PM',
  now: Date,
  firstPing: Date | null,
  lastPing: Date | null,
  hasLeave: boolean,
): Promise<TodayStatus> {
  if (hasLeave) return 'Off';

  const [{ AM, PM }, sys] = await Promise.all([getSessionConfigs(), getSystemConfig()]);
  const cfg = userSession === 'AM' ? AM : PM;
  const date = localDateStr(now, sys.timezone);
  const lateAfterUtc = combineLocalDateAndTime(date, cfg.late_after, sys.timezone);
  const endUtc = combineLocalDateAndTime(date, cfg.end_time, sys.timezone);

  if (firstPing) {
    if (now < endUtc) return 'Checked In';
    const staleMs = sys.presence_staleness_minutes * 60_000;
    if (lastPing && now.getTime() - lastPing.getTime() <= staleMs) return 'Not Checked Out';
    return 'Checked Out';
  }
  if (now < lateAfterUtc) return 'Not Checked In';
  if (now < endUtc) return 'Running Late';
  return 'Not Checked In';
}

export function computeHistoricalStatus(
  firstPing: Date | null,
  sessionLateAfterUtc: Date,
  existingLeave: boolean,
): HistoricalStatus {
  if (existingLeave) return 'leave';
  if (!firstPing) return 'absent';
  return firstPing < sessionLateAfterUtc ? 'early' : 'late';
}
```

- [ ] **Step 4: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/services/statusService.test.ts`
Expected: PASS (12 tests).

- [ ] **Step 5: Commit**

```bash
git add Aegis-Backend/src/services/statusService.ts Aegis-Backend/tests/services/statusService.test.ts
git commit -m "feat(status): add timezone-aware today/historical status derivation"
```

---

## Task 5: Query modules for rooms, devices, presence, attendance history

**Files:**
- Create: `Aegis-Backend/src/db/queries/roomQueries.ts`
- Create: `Aegis-Backend/src/db/queries/deviceQueries.ts`
- Create: `Aegis-Backend/src/db/queries/presenceQueries.ts`
- Create: `Aegis-Backend/src/db/queries/attendanceHistoryQueries.ts`

**Interfaces:**
- Consumes: `pool` from `src/db/pool.ts`; `UserRow` from `userQueries.ts` (auth)
- Produces:
  - **roomQueries:**
    - `interface RoomRow { id_room: number; name: string }`
    - `async function listRooms(): Promise<RoomRow[]>`
    - `async function findRoomById(id: number): Promise<RoomRow | null>`
  - **deviceQueries:**
    - `interface DeviceWithRoom { id_device: number; identifier: string; id_room: number; room_name: string }`
    - `async function listAssignedDevices(): Promise<DeviceWithRoom[]>`
  - **presenceQueries:**
    - `interface PresenceLogRow { id_log: number; id_user: number; id_room: number; timestamp: Date; position_x: number | null; position_y: number | null; battery_level: number | null }`
    - `async function insertPresenceLog(input: { userId: number; roomId: number; positionX: number | null; positionY: number | null; batteryLevel: number | null }): Promise<void>`
    - `async function firstPingForUserInWindow(userId: number, startUtc: Date, endUtc: Date): Promise<Date | null>`
    - `async function lastPingForUserInWindow(userId: number, startUtc: Date, endUtc: Date): Promise<Date | null>`
    - `async function firstAndLastPingBulk(userIds: number[], startUtc: Date, endUtc: Date): Promise<Map<number, { first: Date; last: Date }>>`
    - `interface CurrentRoomRow { id_user: number; id_room: number; last_seen: Date; position_x: number | null; position_y: number | null; log_id: number }`
    - `async function currentRoomPerUser(startUtc: Date, endUtc: Date, stalenessSince: Date): Promise<CurrentRoomRow[]>` — for each user with any log in `[startUtc, endUtc]` whose latest log across all rooms is at `>= stalenessSince`, return that latest log (one row per user).
  - **attendanceHistoryQueries:**
    - `interface AttendanceHistoryRow { id_user: number; date: string; status: 'early' | 'late' | 'leave' | 'absent' }`
    - `async function countByStatus(userId: number): Promise<{ early: number; late: number; leave: number }>`
    - `async function findByUserAndDate(userId: number, date: string): Promise<AttendanceHistoryRow | null>`
    - `async function upsertAttendanceHistory(userId: number, date: string, status: AttendanceHistoryRow['status']): Promise<void>`
    - `async function listHistoriesByUser(userId: number, filter: { month?: number; year?: number }, page: number, perPage: number): Promise<{ list: AttendanceHistoryRow[]; total: number }>`

- [ ] **Step 1: Create `src/db/queries/roomQueries.ts`**

```ts
import { RowDataPacket } from 'mysql2';
import { pool } from '../pool.js';

export interface RoomRow {
  id_room: number;
  name: string;
}

export async function listRooms(): Promise<RoomRow[]> {
  const [rows] = await pool.query<(RoomRow & RowDataPacket)[]>(
    'SELECT `id_room`, `name` FROM `ROOM` ORDER BY `id_room` ASC',
  );
  return rows;
}

export async function findRoomById(id: number): Promise<RoomRow | null> {
  const [rows] = await pool.query<(RoomRow & RowDataPacket)[]>(
    'SELECT `id_room`, `name` FROM `ROOM` WHERE `id_room` = ? LIMIT 1',
    [id],
  );
  return rows[0] ?? null;
}
```

- [ ] **Step 2: Create `src/db/queries/deviceQueries.ts`**

```ts
import { RowDataPacket } from 'mysql2';
import { pool } from '../pool.js';

export interface DeviceWithRoom {
  id_device: number;
  identifier: string;
  id_room: number;
  room_name: string;
}

export async function listAssignedDevices(): Promise<DeviceWithRoom[]> {
  const [rows] = await pool.query<(DeviceWithRoom & RowDataPacket)[]>(
    `SELECT d.\`id_device\`, d.\`identifier\`, d.\`id_room\`, r.\`name\` AS room_name
     FROM \`DEVICE\` d
     JOIN \`ROOM\` r ON r.\`id_room\` = d.\`id_room\`
     WHERE d.\`id_room\` IS NOT NULL
     ORDER BY d.\`id_device\` ASC`,
  );
  return rows;
}
```

- [ ] **Step 3: Create `src/db/queries/presenceQueries.ts`**

```ts
import { RowDataPacket } from 'mysql2';
import { pool } from '../pool.js';

export interface PresenceLogRow {
  id_log: number;
  id_user: number;
  id_room: number;
  timestamp: Date;
  position_x: number | null;
  position_y: number | null;
  battery_level: number | null;
}

export async function insertPresenceLog(input: {
  userId: number;
  roomId: number;
  positionX: number | null;
  positionY: number | null;
  batteryLevel: number | null;
}): Promise<void> {
  await pool.query(
    `INSERT INTO \`PRESENCE_LOG\` (\`id_user\`, \`id_room\`, \`position_x\`, \`position_y\`, \`battery_level\`)
     VALUES (?, ?, ?, ?, ?)`,
    [input.userId, input.roomId, input.positionX, input.positionY, input.batteryLevel],
  );
}

export async function firstPingForUserInWindow(userId: number, startUtc: Date, endUtc: Date): Promise<Date | null> {
  const [rows] = await pool.query<({ ts: Date } & RowDataPacket)[]>(
    'SELECT MIN(`timestamp`) AS ts FROM `PRESENCE_LOG` WHERE `id_user` = ? AND `timestamp` >= ? AND `timestamp` < ?',
    [userId, startUtc, endUtc],
  );
  return rows[0]?.ts ?? null;
}

export async function lastPingForUserInWindow(userId: number, startUtc: Date, endUtc: Date): Promise<Date | null> {
  const [rows] = await pool.query<({ ts: Date } & RowDataPacket)[]>(
    'SELECT MAX(`timestamp`) AS ts FROM `PRESENCE_LOG` WHERE `id_user` = ? AND `timestamp` >= ? AND `timestamp` < ?',
    [userId, startUtc, endUtc],
  );
  return rows[0]?.ts ?? null;
}

export async function firstAndLastPingBulk(
  userIds: number[],
  startUtc: Date,
  endUtc: Date,
): Promise<Map<number, { first: Date; last: Date }>> {
  const out = new Map<number, { first: Date; last: Date }>();
  if (userIds.length === 0) return out;
  const [rows] = await pool.query<({ id_user: number; first: Date; last: Date } & RowDataPacket)[]>(
    `SELECT \`id_user\`, MIN(\`timestamp\`) AS first, MAX(\`timestamp\`) AS last
     FROM \`PRESENCE_LOG\`
     WHERE \`id_user\` IN (?) AND \`timestamp\` >= ? AND \`timestamp\` < ?
     GROUP BY \`id_user\``,
    [userIds, startUtc, endUtc],
  );
  for (const r of rows) out.set(r.id_user, { first: r.first, last: r.last });
  return out;
}

export interface CurrentRoomRow {
  id_user: number;
  id_room: number;
  last_seen: Date;
  position_x: number | null;
  position_y: number | null;
  log_id: number;
}

export async function currentRoomPerUser(
  startUtc: Date,
  endUtc: Date,
  stalenessSince: Date,
): Promise<CurrentRoomRow[]> {
  // Latest log per user in the day-window; only include if that latest is >= stalenessSince.
  const [rows] = await pool.query<(CurrentRoomRow & RowDataPacket)[]>(
    `SELECT p.\`id_user\`, p.\`id_room\`, p.\`timestamp\` AS last_seen,
            p.\`position_x\`, p.\`position_y\`, p.\`id_log\` AS log_id
     FROM \`PRESENCE_LOG\` p
     INNER JOIN (
       SELECT \`id_user\`, MAX(\`timestamp\`) AS max_ts
       FROM \`PRESENCE_LOG\`
       WHERE \`timestamp\` >= ? AND \`timestamp\` < ?
       GROUP BY \`id_user\`
     ) latest ON latest.\`id_user\` = p.\`id_user\` AND latest.max_ts = p.\`timestamp\`
     WHERE p.\`timestamp\` >= ?`,
    [startUtc, endUtc, stalenessSince],
  );
  return rows;
}
```

- [ ] **Step 4: Create `src/db/queries/attendanceHistoryQueries.ts`**

```ts
import { RowDataPacket } from 'mysql2';
import { pool } from '../pool.js';

export interface AttendanceHistoryRow {
  id_user: number;
  date: string;
  status: 'early' | 'late' | 'leave' | 'absent';
}

export async function countByStatus(userId: number): Promise<{ early: number; late: number; leave: number }> {
  const [rows] = await pool.query<({ status: string; c: number } & RowDataPacket)[]>(
    'SELECT `status`, COUNT(*) AS c FROM `ATTENDANCE_HISTORY` WHERE `id_user` = ? GROUP BY `status`',
    [userId],
  );
  const out = { early: 0, late: 0, leave: 0 };
  for (const r of rows) {
    if (r.status === 'early') out.early = r.c;
    else if (r.status === 'late') out.late = r.c;
    else if (r.status === 'leave') out.leave = r.c;
  }
  return out;
}

export async function findByUserAndDate(userId: number, date: string): Promise<AttendanceHistoryRow | null> {
  const [rows] = await pool.query<(AttendanceHistoryRow & RowDataPacket)[]>(
    'SELECT `id_user`, DATE_FORMAT(`date`, "%Y-%m-%d") AS `date`, `status` FROM `ATTENDANCE_HISTORY` WHERE `id_user` = ? AND `date` = ? LIMIT 1',
    [userId, date],
  );
  return rows[0] ?? null;
}

export async function upsertAttendanceHistory(
  userId: number,
  date: string,
  status: AttendanceHistoryRow['status'],
): Promise<void> {
  await pool.query(
    `INSERT INTO \`ATTENDANCE_HISTORY\` (\`id_user\`, \`date\`, \`status\`)
     VALUES (?, ?, ?)
     ON DUPLICATE KEY UPDATE \`status\` = VALUES(\`status\`)`,
    [userId, date, status],
  );
}

export async function listHistoriesByUser(
  userId: number,
  filter: { month?: number; year?: number },
  page: number,
  perPage: number,
): Promise<{ list: AttendanceHistoryRow[]; total: number }> {
  const offset = (page - 1) * perPage;
  const conds: string[] = ['`id_user` = ?'];
  const params: unknown[] = [userId];
  if (filter.year !== undefined) {
    conds.push('YEAR(`date`) = ?');
    params.push(filter.year);
  }
  if (filter.month !== undefined) {
    conds.push('MONTH(`date`) = ?');
    params.push(filter.month);
  }
  const where = 'WHERE ' + conds.join(' AND ');

  const [countRows] = await pool.query<({ c: number } & RowDataPacket)[]>(
    `SELECT COUNT(*) AS c FROM \`ATTENDANCE_HISTORY\` ${where}`,
    params,
  );
  const total = countRows[0]?.c ?? 0;

  const [rows] = await pool.query<(AttendanceHistoryRow & RowDataPacket)[]>(
    `SELECT \`id_user\`, DATE_FORMAT(\`date\`, "%Y-%m-%d") AS \`date\`, \`status\`
     FROM \`ATTENDANCE_HISTORY\`
     ${where}
     ORDER BY \`date\` DESC
     LIMIT ? OFFSET ?`,
    [...params, perPage, offset],
  );

  return { list: rows, total };
}
```

- [ ] **Step 5: Type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add Aegis-Backend/src/db/queries/roomQueries.ts Aegis-Backend/src/db/queries/deviceQueries.ts Aegis-Backend/src/db/queries/presenceQueries.ts Aegis-Backend/src/db/queries/attendanceHistoryQueries.ts
git commit -m "feat(db): add room, device, presence, and attendance history queries"
```

---

## Task 6: userQueries — add listLearners

**Files:**
- Modify: `Aegis-Backend/src/db/queries/userQueries.ts`

**Interfaces:**
- Consumes: nothing new
- Produces (new export): `async function listLearners(filter: { name?: string; session?: 'AM' | 'PM' }, page: number, perPage: number): Promise<{ list: UserRow[]; total: number }>` and `async function listLearnerIds(): Promise<number[]>` and `async function countLearners(): Promise<number>`

- [ ] **Step 1: Append to `src/db/queries/userQueries.ts`**

Add these exports at the end of the file:

```ts
export async function listLearners(
  filter: { name?: string; session?: 'AM' | 'PM' },
  page: number,
  perPage: number,
): Promise<{ list: UserRow[]; total: number }> {
  const conds: string[] = [`\`role\` = 'learner'`];
  const params: unknown[] = [];
  if (filter.name !== undefined && filter.name !== '') {
    conds.push(`TRIM(CONCAT_WS(' ', \`first_name\`, \`last_name\`)) LIKE ?`);
    params.push(`%${filter.name}%`);
  }
  if (filter.session !== undefined) {
    conds.push('`session` = ?');
    params.push(filter.session);
  }
  const where = 'WHERE ' + conds.join(' AND ');

  const [countRows] = await pool.query<({ c: number } & RowDataPacket)[]>(
    `SELECT COUNT(*) AS c FROM \`USER\` ${where}`,
    params,
  );
  const total = countRows[0]?.c ?? 0;

  const offset = (page - 1) * perPage;
  const [rows] = await pool.query<(UserRow & RowDataPacket)[]>(
    `SELECT * FROM \`USER\` ${where} ORDER BY \`first_name\` ASC, \`last_name\` ASC LIMIT ? OFFSET ?`,
    [...params, perPage, offset],
  );
  return { list: rows, total };
}

export async function listLearnerIds(): Promise<number[]> {
  const [rows] = await pool.query<({ id_user: number } & RowDataPacket)[]>(
    "SELECT `id_user` FROM `USER` WHERE `role` = 'learner'",
  );
  return rows.map((r) => r.id_user);
}

export async function countLearners(): Promise<number> {
  const [rows] = await pool.query<({ c: number } & RowDataPacket)[]>(
    "SELECT COUNT(*) AS c FROM `USER` WHERE `role` = 'learner'",
  );
  return rows[0]?.c ?? 0;
}
```

Also ensure `RowDataPacket` is imported at the top — it already is.

- [ ] **Step 2: Type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add Aegis-Backend/src/db/queries/userQueries.ts
git commit -m "feat(db): add listLearners and helper queries for admin views"
```

---

## Task 7: presenceService + rate-limit middleware

**Files:**
- Create: `Aegis-Backend/src/services/presenceService.ts`
- Create: `Aegis-Backend/src/middleware/presenceRateLimit.ts`
- Create: `Aegis-Backend/tests/services/presenceService.test.ts`

**Interfaces:**
- Consumes: `insertPresenceLog` (presenceQueries), `findRoomById` (roomQueries), `AppError`
- Produces:
  - `async function recordPresence(userId: number, input: { room_id: number; position_x?: number | null; position_y?: number | null; battery_level?: number | null }): Promise<void>` — throws `AppError('invalid_request')` if room missing
  - `presenceRateLimit: RequestHandler` — 20 req / learner / minute; key = `req.user.id`

- [ ] **Step 1: Write failing test `tests/services/presenceService.test.ts`**

```ts
import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

vi.mock('../../src/db/queries/roomQueries.js', () => ({
  listRooms: vi.fn(),
  findRoomById: vi.fn(),
}));
vi.mock('../../src/db/queries/presenceQueries.js', () => ({
  insertPresenceLog: vi.fn(),
  firstPingForUserInWindow: vi.fn(),
  lastPingForUserInWindow: vi.fn(),
  firstAndLastPingBulk: vi.fn(),
  currentRoomPerUser: vi.fn(),
}));

const load = async () => {
  const svc = await import('../../src/services/presenceService.js');
  const rq = await import('../../src/db/queries/roomQueries.js');
  const pq = await import('../../src/db/queries/presenceQueries.js');
  return { svc, rq, pq };
};

beforeEach(() => vi.clearAllMocks());

describe('recordPresence', () => {
  it('inserts log when room exists', async () => {
    const { svc, rq, pq } = await load();
    (rq.findRoomById as any).mockResolvedValue({ id_room: 3, name: 'Lab' });
    await svc.recordPresence(42, { room_id: 3, position_x: 1, position_y: 2, battery_level: 88 });
    expect(pq.insertPresenceLog).toHaveBeenCalledWith({
      userId: 42, roomId: 3, positionX: 1, positionY: 2, batteryLevel: 88,
    });
  });

  it('rejects when room missing', async () => {
    const { svc, rq } = await load();
    (rq.findRoomById as any).mockResolvedValue(null);
    await expect(svc.recordPresence(42, { room_id: 99 })).rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('coerces optional fields to null', async () => {
    const { svc, rq, pq } = await load();
    (rq.findRoomById as any).mockResolvedValue({ id_room: 3, name: 'Lab' });
    await svc.recordPresence(42, { room_id: 3 });
    expect(pq.insertPresenceLog).toHaveBeenCalledWith({
      userId: 42, roomId: 3, positionX: null, positionY: null, batteryLevel: null,
    });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/services/presenceService.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Create `src/services/presenceService.ts`**

```ts
import { AppError } from '../lib/errors.js';
import { findRoomById } from '../db/queries/roomQueries.js';
import { insertPresenceLog } from '../db/queries/presenceQueries.js';

export async function recordPresence(
  userId: number,
  input: { room_id: number; position_x?: number | null; position_y?: number | null; battery_level?: number | null },
): Promise<void> {
  const room = await findRoomById(input.room_id);
  if (!room) throw new AppError('invalid_request', 'Unknown room_id');
  await insertPresenceLog({
    userId,
    roomId: input.room_id,
    positionX: input.position_x ?? null,
    positionY: input.position_y ?? null,
    batteryLevel: input.battery_level ?? null,
  });
}
```

- [ ] **Step 4: Create `src/middleware/presenceRateLimit.ts`**

```ts
import rateLimit from 'express-rate-limit';
import type { Request } from 'express';

export const presenceRateLimit = rateLimit({
  windowMs: 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req: Request) => String(req.user?.id ?? req.ip ?? 'unknown'),
  message: { error: 'too_many_requests', message: 'Too many requests — please try again later' },
});
```

- [ ] **Step 5: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/services/presenceService.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 6: Type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
git add Aegis-Backend/src/services/presenceService.ts Aegis-Backend/src/middleware/presenceRateLimit.ts Aegis-Backend/tests/services/presenceService.test.ts
git commit -m "feat(presence): add ingestion service and per-learner rate limit"
```

---

## Task 8: dashboardService (L2 + A1)

**Files:**
- Create: `Aegis-Backend/src/services/dashboardService.ts`
- Create: `Aegis-Backend/tests/services/dashboardService.test.ts`

**Interfaces:**
- Consumes: `countByStatus`, `findByUserAndDate` (attendanceHistoryQueries); `firstPingForUserInWindow`, `lastPingForUserInWindow`, `firstAndLastPingBulk` (presenceQueries); `getSessionConfigs`, `getSystemConfig` (configService); `computeTodayStatus`, `localDayBoundsUtc`, `localDateStr`, `combineLocalDateAndTime` (statusService); `findUserById`, `listLearnerIds` (userQueries)
- Produces:
  - `async function getLearnerDashboard(userId: number, now: Date): Promise<{ total_attendance: number; total_late: number; leave_taken: number; today_status: TodayStatus }>`
  - `async function getAbsenceSummary(now: Date): Promise<{ present_summary: { on_time: number; late_clock_in: number }; absent_summary: { absent: number; no_clock_in: number } }>`

- [ ] **Step 1: Write failing test `tests/services/dashboardService.test.ts`**

```ts
import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

vi.mock('../../src/db/queries/attendanceHistoryQueries.js', () => ({
  countByStatus: vi.fn(),
  findByUserAndDate: vi.fn(),
  upsertAttendanceHistory: vi.fn(),
  listHistoriesByUser: vi.fn(),
}));
vi.mock('../../src/db/queries/presenceQueries.js', () => ({
  insertPresenceLog: vi.fn(),
  firstPingForUserInWindow: vi.fn(),
  lastPingForUserInWindow: vi.fn(),
  firstAndLastPingBulk: vi.fn(),
  currentRoomPerUser: vi.fn(),
}));
vi.mock('../../src/db/queries/userQueries.js', () => ({
  findUserById: vi.fn(),
  findUserByUsername: vi.fn(),
  insertUser: vi.fn(),
  listLearners: vi.fn(),
  listLearnerIds: vi.fn(),
  countLearners: vi.fn(),
}));
vi.mock('../../src/services/configService.js', () => ({
  getSessionConfigs: vi.fn(),
  getSystemConfig: vi.fn(),
}));

const load = async () => {
  const svc = await import('../../src/services/dashboardService.js');
  const ah = await import('../../src/db/queries/attendanceHistoryQueries.js');
  const pq = await import('../../src/db/queries/presenceQueries.js');
  const uq = await import('../../src/db/queries/userQueries.js');
  const cfg = await import('../../src/services/configService.js');
  return { svc, ah, pq, uq, cfg };
};

const AM = { session: 'AM' as const, start_time: '08:00:00', late_after: '08:15:00', end_time: '12:00:00' };
const PM = { session: 'PM' as const, start_time: '13:00:00', late_after: '13:15:00', end_time: '17:00:00' };

beforeEach(() => vi.clearAllMocks());

describe('getLearnerDashboard', () => {
  it('rolls up counters and computes today_status', async () => {
    const { svc, ah, pq, uq, cfg } = await load();
    (uq.findUserById as any).mockResolvedValue({ id_user: 42, session: 'AM', role: 'learner', username: 'a', first_name: 'A', last_name: 'B', email: 'a@x', password: '' });
    (ah.countByStatus as any).mockResolvedValue({ early: 80, late: 12, leave: 3 });
    (ah.findByUserAndDate as any).mockResolvedValue(null);
    (pq.firstPingForUserInWindow as any).mockResolvedValue(new Date('2026-07-03T01:10:00Z'));
    (pq.lastPingForUserInWindow as any).mockResolvedValue(new Date('2026-07-03T01:10:00Z'));
    (cfg.getSessionConfigs as any).mockResolvedValue({ AM, PM });
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' });

    const r = await svc.getLearnerDashboard(42, new Date('2026-07-03T02:00:00Z'));
    expect(r.total_attendance).toBe(92);
    expect(r.total_late).toBe(12);
    expect(r.leave_taken).toBe(3);
    expect(r.today_status).toBe('Checked In');
  });
});

describe('getAbsenceSummary', () => {
  it('buckets learners by first-ping vs session windows', async () => {
    const { svc, pq, uq, cfg } = await load();
    (cfg.getSessionConfigs as any).mockResolvedValue({ AM, PM });
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' });
    (uq.listLearnerIds as any).mockResolvedValue([1, 2, 3, 4]);
    // now = 09:00 local (AM window still open)
    const now = new Date('2026-07-03T02:00:00Z');
    // 1: on_time (first ping 08:05 local); 2: late_clock_in (08:20 local); 3: no ping, still in window; 4: no ping
    (pq.firstAndLastPingBulk as any).mockResolvedValue(new Map([
      [1, { first: new Date('2026-07-03T01:05:00Z'), last: new Date('2026-07-03T01:05:00Z') }],
      [2, { first: new Date('2026-07-03T01:20:00Z'), last: new Date('2026-07-03T01:20:00Z') }],
    ]));
    (uq.findUserById as any).mockImplementation(async (id: number) => ({ id_user: id, session: 'AM', role: 'learner', username: 'x', first_name: 'x', last_name: 'y', email: 'a@x', password: '' }));

    const r = await svc.getAbsenceSummary(now);
    expect(r.present_summary.on_time).toBe(1);
    expect(r.present_summary.late_clock_in).toBe(1);
    expect(r.absent_summary.no_clock_in).toBe(2);
    expect(r.absent_summary.absent).toBe(0);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/services/dashboardService.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Create `src/services/dashboardService.ts`**

```ts
import { AppError } from '../lib/errors.js';
import {
  countByStatus,
  findByUserAndDate,
} from '../db/queries/attendanceHistoryQueries.js';
import {
  firstPingForUserInWindow,
  lastPingForUserInWindow,
  firstAndLastPingBulk,
} from '../db/queries/presenceQueries.js';
import { findUserById, listLearnerIds } from '../db/queries/userQueries.js';
import { getSessionConfigs, getSystemConfig } from './configService.js';
import {
  computeTodayStatus,
  localDayBoundsUtc,
  localDateStr,
  combineLocalDateAndTime,
  TodayStatus,
} from './statusService.js';

export async function getLearnerDashboard(
  userId: number,
  now: Date,
): Promise<{ total_attendance: number; total_late: number; leave_taken: number; today_status: TodayStatus }> {
  const user = await findUserById(userId);
  if (!user) throw new AppError('not_found', 'User not found');

  const [counts, sys] = await Promise.all([countByStatus(userId), getSystemConfig()]);
  const total_attendance = counts.early + counts.late;
  const total_late = counts.late;
  const leave_taken = counts.leave;

  const { startUtc, endUtc } = localDayBoundsUtc(now, sys.timezone);
  const [first, last, todayRow] = await Promise.all([
    firstPingForUserInWindow(userId, startUtc, endUtc),
    lastPingForUserInWindow(userId, startUtc, endUtc),
    findByUserAndDate(userId, localDateStr(now, sys.timezone)),
  ]);
  const hasLeave = todayRow?.status === 'leave';
  const today_status = await computeTodayStatus(user.session, now, first, last, hasLeave);
  return { total_attendance, total_late, leave_taken, today_status };
}

export async function getAbsenceSummary(
  now: Date,
): Promise<{ present_summary: { on_time: number; late_clock_in: number }; absent_summary: { absent: number; no_clock_in: number } }> {
  const [{ AM, PM }, sys, learnerIds] = await Promise.all([
    getSessionConfigs(),
    getSystemConfig(),
    listLearnerIds(),
  ]);
  const { startUtc, endUtc } = localDayBoundsUtc(now, sys.timezone);
  const pings = await firstAndLastPingBulk(learnerIds, startUtc, endUtc);

  const date = localDateStr(now, sys.timezone);
  const lateAfterUtc = { AM: combineLocalDateAndTime(date, AM.late_after, sys.timezone), PM: combineLocalDateAndTime(date, PM.late_after, sys.timezone) };
  const endTimeUtc = { AM: combineLocalDateAndTime(date, AM.end_time, sys.timezone), PM: combineLocalDateAndTime(date, PM.end_time, sys.timezone) };

  let on_time = 0, late_clock_in = 0, absent = 0, no_clock_in = 0;

  // Fetch every learner and their today attendance row in parallel.
  const learners = await Promise.all(learnerIds.map((id) => findUserById(id)));
  const leaveRows = await Promise.all(learnerIds.map((id) => findByUserAndDate(id, date)));

  for (let i = 0; i < learners.length; i++) {
    const l = learners[i];
    if (!l) continue;
    if (leaveRows[i]?.status === 'leave') { absent++; continue; }
    const p = pings.get(l.id_user);
    const s = l.session;
    if (p) {
      if (p.first <= lateAfterUtc[s]) on_time++;
      else late_clock_in++;
    } else {
      if (now < endTimeUtc[s]) no_clock_in++;
      else absent++;
    }
  }
  return { present_summary: { on_time, late_clock_in }, absent_summary: { absent, no_clock_in } };
}
```

- [ ] **Step 4: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/services/dashboardService.test.ts`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Aegis-Backend/src/services/dashboardService.ts Aegis-Backend/tests/services/dashboardService.test.ts
git commit -m "feat(dashboard): add learner dashboard and admin absence summary services"
```

---

## Task 9: overviewService (A2)

**Files:**
- Create: `Aegis-Backend/src/services/overviewService.ts`
- Create: `Aegis-Backend/tests/services/overviewService.test.ts`

**Interfaces:**
- Consumes: `listLearners` (userQueries), `firstAndLastPingBulk` (presenceQueries), `findByUserAndDate` (attendanceHistoryQueries), `configService`, `statusService`
- Produces:
  - `async function getOverview(now: Date, filter: { name?: string; session?: 'AM' | 'PM' }, page: number, perPage: number): Promise<{ list: Array<{ name: string; session: 'AM' | 'PM'; clocked_in_at: string | null; clocked_out_at: string | null; status: TodayStatus }>; page: number; per_page: number; total: number }>`

Name formatting: `TRIM([first_name] + ' ' + [last_name])`; if both null, use `username`.

- [ ] **Step 1: Write failing test `tests/services/overviewService.test.ts`**

```ts
import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';

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
  findUserByUsername: vi.fn(),
  insertUser: vi.fn(),
  listLearners: vi.fn(),
  listLearnerIds: vi.fn(),
  countLearners: vi.fn(),
}));
vi.mock('../../src/db/queries/presenceQueries.js', () => ({
  insertPresenceLog: vi.fn(),
  firstPingForUserInWindow: vi.fn(),
  lastPingForUserInWindow: vi.fn(),
  firstAndLastPingBulk: vi.fn(),
  currentRoomPerUser: vi.fn(),
}));
vi.mock('../../src/db/queries/attendanceHistoryQueries.js', () => ({
  countByStatus: vi.fn(),
  findByUserAndDate: vi.fn(),
  upsertAttendanceHistory: vi.fn(),
  listHistoriesByUser: vi.fn(),
}));
vi.mock('../../src/services/configService.js', () => ({
  getSessionConfigs: vi.fn(),
  getSystemConfig: vi.fn(),
}));

const load = async () => {
  const svc = await import('../../src/services/overviewService.js');
  const uq = await import('../../src/db/queries/userQueries.js');
  const pq = await import('../../src/db/queries/presenceQueries.js');
  const cfg = await import('../../src/services/configService.js');
  return { svc, uq, pq, cfg };
};

const AM = { session: 'AM' as const, start_time: '08:00:00', late_after: '08:15:00', end_time: '12:00:00' };
const PM = { session: 'PM' as const, start_time: '13:00:00', late_after: '13:15:00', end_time: '17:00:00' };

beforeEach(() => vi.clearAllMocks());

describe('getOverview', () => {
  it('returns paged list with clocked times and today_status', async () => {
    const { svc, uq, pq, cfg } = await load();
    (cfg.getSessionConfigs as any).mockResolvedValue({ AM, PM });
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' });
    (uq.listLearners as any).mockResolvedValue({
      list: [
        { id_user: 1, username: 'alice', password: '', email: 'a@x', role: 'learner', first_name: 'Alice', last_name: 'Doe', session: 'AM' },
        { id_user: 2, username: 'bob', password: '', email: 'b@x', role: 'learner', first_name: null, last_name: null, session: 'PM' },
      ],
      total: 2,
    });
    (pq.firstAndLastPingBulk as any).mockResolvedValue(new Map([
      [1, { first: new Date('2026-07-03T01:10:00Z'), last: new Date('2026-07-03T01:10:00Z') }],
    ]));

    const now = new Date('2026-07-03T02:00:00Z');
    const r = await svc.getOverview(now, {}, 1, 20);
    expect(r.list).toHaveLength(2);
    expect(r.list[0].name).toBe('Alice Doe');
    expect(r.list[0].clocked_in_at).toBe('2026-07-03T01:10:00.000Z');
    expect(r.list[0].status).toBe('Checked In');
    expect(r.list[1].name).toBe('bob');
    expect(r.list[1].clocked_in_at).toBeNull();
    expect(r.total).toBe(2);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/services/overviewService.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Create `src/services/overviewService.ts`**

```ts
import { listLearners, UserRow } from '../db/queries/userQueries.js';
import { firstAndLastPingBulk } from '../db/queries/presenceQueries.js';
import { findByUserAndDate } from '../db/queries/attendanceHistoryQueries.js';
import { getSessionConfigs, getSystemConfig } from './configService.js';
import { computeTodayStatus, localDayBoundsUtc, localDateStr, TodayStatus } from './statusService.js';

function displayName(row: UserRow): string {
  const parts = [row.first_name, row.last_name].filter((x): x is string => !!x);
  const joined = parts.join(' ').trim();
  return joined || row.username;
}

export async function getOverview(
  now: Date,
  filter: { name?: string; session?: 'AM' | 'PM' },
  page: number,
  perPage: number,
): Promise<{
  list: Array<{ name: string; session: 'AM' | 'PM'; clocked_in_at: string | null; clocked_out_at: string | null; status: TodayStatus }>;
  page: number;
  per_page: number;
  total: number;
}> {
  const { list: learners, total } = await listLearners(filter, page, perPage);
  if (learners.length === 0) {
    return { list: [], page, per_page: perPage, total };
  }
  const [sys, pings] = await Promise.all([
    getSystemConfig(),
    (async () => {
      const { startUtc, endUtc } = localDayBoundsUtc(now, (await getSystemConfig()).timezone);
      return firstAndLastPingBulk(learners.map((l) => l.id_user), startUtc, endUtc);
    })(),
  ]);
  const date = localDateStr(now, sys.timezone);

  const leaveRows = await Promise.all(learners.map((l) => findByUserAndDate(l.id_user, date)));

  const list = await Promise.all(
    learners.map(async (l, idx) => {
      const p = pings.get(l.id_user);
      const first = p?.first ?? null;
      const last = p?.last ?? null;
      const hasLeave = leaveRows[idx]?.status === 'leave';
      const status = await computeTodayStatus(l.session, now, first, last, hasLeave);
      return {
        name: displayName(l),
        session: l.session,
        clocked_in_at: first ? first.toISOString() : null,
        clocked_out_at: last ? last.toISOString() : null,
        status,
      };
    }),
  );

  return { list, page, per_page: perPage, total };
}
```

- [ ] **Step 4: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/services/overviewService.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Aegis-Backend/src/services/overviewService.ts Aegis-Backend/tests/services/overviewService.test.ts
git commit -m "feat(admin): add overview service"
```

---

## Task 10: roomsService (A3, A4, A5, A6)

**Files:**
- Create: `Aegis-Backend/src/services/roomsService.ts`
- Create: `Aegis-Backend/tests/services/roomsService.test.ts`

**Interfaces:**
- Consumes: `listRooms`, `findRoomById`; `currentRoomPerUser`, `firstPingForUserInWindow`; `findUserById`; `configService`; `AppError`
- Produces:
  - `async function listAllRooms(): Promise<Array<{ id: number; name: string }>>`
  - `async function getRoomMap(roomId: number, now: Date): Promise<{ list: Array<{ id: number; user: { id: number; name: string; session: 'AM' | 'PM' | null }; x: number | null; y: number | null }> }>` — throws `AppError('not_found')` if room missing
  - `async function getRoomCurrentOccupants(roomId: number, now: Date): Promise<{ list: Array<{ user: { id: number; name: string; session: 'AM' | 'PM' | null }; duration_seconds: number; status: TodayStatus }> }>`
  - `async function getRoomAdditionalData(roomId: number, now: Date): Promise<{ room_temperature: number; humidity: number; people_in_room: number }>` — mocked constants + live count

Name/session helpers match `overviewService.displayName` behavior; for admin users session is `null`.

- [ ] **Step 1: Write failing test `tests/services/roomsService.test.ts`**

```ts
import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

vi.mock('../../src/db/queries/roomQueries.js', () => ({ listRooms: vi.fn(), findRoomById: vi.fn() }));
vi.mock('../../src/db/queries/presenceQueries.js', () => ({
  insertPresenceLog: vi.fn(),
  firstPingForUserInWindow: vi.fn(),
  lastPingForUserInWindow: vi.fn(),
  firstAndLastPingBulk: vi.fn(),
  currentRoomPerUser: vi.fn(),
}));
vi.mock('../../src/db/queries/userQueries.js', () => ({
  findUserById: vi.fn(),
  findUserByUsername: vi.fn(),
  insertUser: vi.fn(),
  listLearners: vi.fn(),
  listLearnerIds: vi.fn(),
  countLearners: vi.fn(),
}));
vi.mock('../../src/db/queries/attendanceHistoryQueries.js', () => ({
  countByStatus: vi.fn(),
  findByUserAndDate: vi.fn(),
  upsertAttendanceHistory: vi.fn(),
  listHistoriesByUser: vi.fn(),
}));
vi.mock('../../src/services/configService.js', () => ({
  getSessionConfigs: vi.fn(),
  getSystemConfig: vi.fn(),
}));

const load = async () => {
  const svc = await import('../../src/services/roomsService.js');
  const rq = await import('../../src/db/queries/roomQueries.js');
  const pq = await import('../../src/db/queries/presenceQueries.js');
  const uq = await import('../../src/db/queries/userQueries.js');
  const cfg = await import('../../src/services/configService.js');
  return { svc, rq, pq, uq, cfg };
};

const AM = { session: 'AM' as const, start_time: '08:00:00', late_after: '08:15:00', end_time: '12:00:00' };
const PM = { session: 'PM' as const, start_time: '13:00:00', late_after: '13:15:00', end_time: '17:00:00' };

beforeEach(() => vi.clearAllMocks());

describe('listAllRooms', () => {
  it('maps DB rows to id/name', async () => {
    const { svc, rq } = await load();
    (rq.listRooms as any).mockResolvedValue([{ id_room: 1, name: 'Lab A' }, { id_room: 2, name: 'Lab B' }]);
    const r = await svc.listAllRooms();
    expect(r).toEqual([{ id: 1, name: 'Lab A' }, { id: 2, name: 'Lab B' }]);
  });
});

describe('getRoomMap', () => {
  it('throws not_found when room missing', async () => {
    const { svc, rq } = await load();
    (rq.findRoomById as any).mockResolvedValue(null);
    await expect(svc.getRoomMap(99, new Date('2026-07-03T02:00:00Z'))).rejects.toMatchObject({ code: 'not_found' });
  });

  it('returns only users whose current room is this room', async () => {
    const { svc, rq, pq, uq, cfg } = await load();
    (rq.findRoomById as any).mockResolvedValue({ id_room: 1, name: 'Lab A' });
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' });
    (pq.currentRoomPerUser as any).mockResolvedValue([
      { id_user: 42, id_room: 1, last_seen: new Date(), position_x: 1, position_y: 2, log_id: 100 },
      { id_user: 43, id_room: 2, last_seen: new Date(), position_x: 3, position_y: 4, log_id: 101 },
    ]);
    (uq.findUserById as any).mockImplementation(async (id: number) => ({
      id_user: id, username: `u${id}`, password: '', email: '', role: 'learner', first_name: `U${id}`, last_name: null, session: 'AM',
    }));

    const r = await svc.getRoomMap(1, new Date('2026-07-03T02:00:00Z'));
    expect(r.list).toHaveLength(1);
    expect(r.list[0].user.id).toBe(42);
    expect(r.list[0].x).toBe(1);
  });
});

describe('getRoomCurrentOccupants', () => {
  it('computes duration and status', async () => {
    const { svc, rq, pq, uq, cfg } = await load();
    (rq.findRoomById as any).mockResolvedValue({ id_room: 1, name: 'Lab A' });
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' });
    (cfg.getSessionConfigs as any).mockResolvedValue({ AM, PM });
    const now = new Date('2026-07-03T02:00:00Z');
    (pq.currentRoomPerUser as any).mockResolvedValue([
      { id_user: 42, id_room: 1, last_seen: new Date('2026-07-03T01:55:00Z'), position_x: null, position_y: null, log_id: 100 },
    ]);
    (pq.firstPingForUserInWindow as any).mockResolvedValue(new Date('2026-07-03T01:00:00Z'));
    (uq.findUserById as any).mockResolvedValue({ id_user: 42, username: 'a', password: '', email: '', role: 'learner', first_name: 'A', last_name: 'Z', session: 'AM' });

    const r = await svc.getRoomCurrentOccupants(1, now);
    expect(r.list).toHaveLength(1);
    expect(r.list[0].duration_seconds).toBe(60 * 60);
    expect(r.list[0].status).toBe('Checked In');
  });
});

describe('getRoomAdditionalData', () => {
  it('returns fixed temp/humidity and live people count', async () => {
    const { svc, rq, pq, cfg } = await load();
    (rq.findRoomById as any).mockResolvedValue({ id_room: 1, name: 'Lab A' });
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' });
    (pq.currentRoomPerUser as any).mockResolvedValue([
      { id_user: 42, id_room: 1, last_seen: new Date(), position_x: null, position_y: null, log_id: 1 },
      { id_user: 43, id_room: 1, last_seen: new Date(), position_x: null, position_y: null, log_id: 2 },
      { id_user: 44, id_room: 2, last_seen: new Date(), position_x: null, position_y: null, log_id: 3 },
    ]);

    const r = await svc.getRoomAdditionalData(1, new Date('2026-07-03T02:00:00Z'));
    expect(r.room_temperature).toBe(24.5);
    expect(r.humidity).toBe(62);
    expect(r.people_in_room).toBe(2);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/services/roomsService.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Create `src/services/roomsService.ts`**

```ts
import { AppError } from '../lib/errors.js';
import { listRooms, findRoomById } from '../db/queries/roomQueries.js';
import { currentRoomPerUser, firstPingForUserInWindow } from '../db/queries/presenceQueries.js';
import { findUserById, UserRow } from '../db/queries/userQueries.js';
import { findByUserAndDate } from '../db/queries/attendanceHistoryQueries.js';
import { getSystemConfig } from './configService.js';
import { computeTodayStatus, localDayBoundsUtc, localDateStr, TodayStatus } from './statusService.js';

function displayName(row: UserRow): string {
  const parts = [row.first_name, row.last_name].filter((x): x is string => !!x);
  const joined = parts.join(' ').trim();
  return joined || row.username;
}

function userResource(row: UserRow): { id: number; name: string; session: 'AM' | 'PM' | null } {
  return {
    id: row.id_user,
    name: displayName(row),
    session: row.role === 'learner' ? row.session : null,
  };
}

export async function listAllRooms(): Promise<Array<{ id: number; name: string }>> {
  const rows = await listRooms();
  return rows.map((r) => ({ id: r.id_room, name: r.name }));
}

async function ensureRoomExists(roomId: number): Promise<void> {
  const room = await findRoomById(roomId);
  if (!room) throw new AppError('not_found', 'Room not found');
}

async function currentUsersInRoom(roomId: number, now: Date) {
  const sys = await getSystemConfig();
  const { startUtc, endUtc } = localDayBoundsUtc(now, sys.timezone);
  const stalenessSince = new Date(now.getTime() - sys.presence_staleness_minutes * 60_000);
  const rows = await currentRoomPerUser(startUtc, endUtc, stalenessSince);
  return rows.filter((r) => r.id_room === roomId);
}

export async function getRoomMap(
  roomId: number,
  now: Date,
): Promise<{ list: Array<{ id: number; user: { id: number; name: string; session: 'AM' | 'PM' | null }; x: number | null; y: number | null }> }> {
  await ensureRoomExists(roomId);
  const rows = await currentUsersInRoom(roomId, now);
  const users = await Promise.all(rows.map((r) => findUserById(r.id_user)));
  const list = rows.map((r, i) => {
    const u = users[i];
    if (!u) return null;
    return { id: r.log_id, user: userResource(u), x: r.position_x, y: r.position_y };
  }).filter((x): x is NonNullable<typeof x> => x !== null);
  return { list };
}

export async function getRoomCurrentOccupants(
  roomId: number,
  now: Date,
): Promise<{ list: Array<{ user: { id: number; name: string; session: 'AM' | 'PM' | null }; duration_seconds: number; status: TodayStatus }> }> {
  await ensureRoomExists(roomId);
  const sys = await getSystemConfig();
  const { startUtc, endUtc } = localDayBoundsUtc(now, sys.timezone);
  const rows = await currentUsersInRoom(roomId, now);
  const enriched = await Promise.all(rows.map(async (r) => {
    const user = await findUserById(r.id_user);
    if (!user) return null;
    const first = await firstPingForUserInWindow(r.id_user, startUtc, endUtc);
    const leaveRow = await findByUserAndDate(r.id_user, localDateStr(now, sys.timezone));
    const hasLeave = leaveRow?.status === 'leave';
    const status = await computeTodayStatus(user.session, now, first, r.last_seen, hasLeave);
    const duration_seconds = first ? Math.max(0, Math.floor((now.getTime() - first.getTime()) / 1000)) : 0;
    return { user: userResource(user), duration_seconds, status };
  }));
  return { list: enriched.filter((x): x is NonNullable<typeof x> => x !== null) };
}

export async function getRoomAdditionalData(
  roomId: number,
  now: Date,
): Promise<{ room_temperature: number; humidity: number; people_in_room: number }> {
  await ensureRoomExists(roomId);
  const rows = await currentUsersInRoom(roomId, now);
  return { room_temperature: 24.5, humidity: 62, people_in_room: rows.length };
}
```

- [ ] **Step 4: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/services/roomsService.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Aegis-Backend/src/services/roomsService.ts Aegis-Backend/tests/services/roomsService.test.ts
git commit -m "feat(admin): add rooms service (list, map, occupants, additional-data)"
```

---

## Task 11: rollupService

**Files:**
- Create: `Aegis-Backend/src/services/rollupService.ts`
- Create: `Aegis-Backend/tests/services/rollupService.test.ts`

**Interfaces:**
- Consumes: `getSessionConfigs`, `getSystemConfig` (configService); `firstPingForUserInWindow` (presenceQueries); `findByUserAndDate`, `upsertAttendanceHistory` (attendanceHistoryQueries); `findUserById`, `listLearnerIds` (userQueries); `combineLocalDateAndTime` (statusService); `AppError`
- Produces:
  - `async function runRollup(input: { date?: string; userId?: number; now?: Date }): Promise<{ processed: number; skipped_leave: number }>`

`date` defaults to yesterday in the configured timezone. `userId` defaults to all learners.

- [ ] **Step 1: Write failing test `tests/services/rollupService.test.ts`**

```ts
import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

vi.mock('../../src/db/queries/attendanceHistoryQueries.js', () => ({
  countByStatus: vi.fn(),
  findByUserAndDate: vi.fn(),
  upsertAttendanceHistory: vi.fn(),
  listHistoriesByUser: vi.fn(),
}));
vi.mock('../../src/db/queries/presenceQueries.js', () => ({
  insertPresenceLog: vi.fn(),
  firstPingForUserInWindow: vi.fn(),
  lastPingForUserInWindow: vi.fn(),
  firstAndLastPingBulk: vi.fn(),
  currentRoomPerUser: vi.fn(),
}));
vi.mock('../../src/db/queries/userQueries.js', () => ({
  findUserById: vi.fn(),
  findUserByUsername: vi.fn(),
  insertUser: vi.fn(),
  listLearners: vi.fn(),
  listLearnerIds: vi.fn(),
  countLearners: vi.fn(),
}));
vi.mock('../../src/services/configService.js', () => ({
  getSessionConfigs: vi.fn(),
  getSystemConfig: vi.fn(),
}));

const load = async () => {
  const svc = await import('../../src/services/rollupService.js');
  const ah = await import('../../src/db/queries/attendanceHistoryQueries.js');
  const pq = await import('../../src/db/queries/presenceQueries.js');
  const uq = await import('../../src/db/queries/userQueries.js');
  const cfg = await import('../../src/services/configService.js');
  return { svc, ah, pq, uq, cfg };
};

const AM = { session: 'AM' as const, start_time: '08:00:00', late_after: '08:15:00', end_time: '12:00:00' };
const PM = { session: 'PM' as const, start_time: '13:00:00', late_after: '13:15:00', end_time: '17:00:00' };

beforeEach(() => vi.clearAllMocks());

describe('runRollup', () => {
  it('processes all learners for yesterday when no args', async () => {
    const { svc, ah, pq, uq, cfg } = await load();
    (cfg.getSessionConfigs as any).mockResolvedValue({ AM, PM });
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' });
    (uq.listLearnerIds as any).mockResolvedValue([1, 2, 3]);
    (uq.findUserById as any).mockImplementation(async (id: number) => ({ id_user: id, session: 'AM', role: 'learner', username: 'x', first_name: 'x', last_name: 'y', email: 'a@x', password: '' }));
    (ah.findByUserAndDate as any).mockImplementation(async (id: number) => id === 2 ? { id_user: 2, date: '2026-07-02', status: 'leave' } : null);
    (pq.firstPingForUserInWindow as any).mockImplementation(async (id: number) => id === 1 ? new Date('2026-07-02T01:10:00Z') : null);

    const r = await svc.runRollup({ now: new Date('2026-07-03T02:00:00Z') });
    expect(r.processed).toBe(2);      // user 1 (early) and 3 (absent)
    expect(r.skipped_leave).toBe(1);  // user 2

    expect(ah.upsertAttendanceHistory).toHaveBeenCalledWith(1, '2026-07-02', 'early');
    expect(ah.upsertAttendanceHistory).toHaveBeenCalledWith(3, '2026-07-02', 'absent');
    expect(ah.upsertAttendanceHistory).not.toHaveBeenCalledWith(2, expect.anything(), expect.anything());
  });

  it('processes a single user when userId given', async () => {
    const { svc, ah, pq, uq, cfg } = await load();
    (cfg.getSessionConfigs as any).mockResolvedValue({ AM, PM });
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' });
    (uq.findUserById as any).mockResolvedValue({ id_user: 5, session: 'PM', role: 'learner', username: 'x', first_name: 'x', last_name: 'y', email: 'a@x', password: '' });
    (ah.findByUserAndDate as any).mockResolvedValue(null);
    (pq.firstPingForUserInWindow as any).mockResolvedValue(new Date('2026-07-02T06:20:00Z')); // 13:20 local = after PM late_after

    const r = await svc.runRollup({ userId: 5, date: '2026-07-02' });
    expect(r.processed).toBe(1);
    expect(r.skipped_leave).toBe(0);
    expect(ah.upsertAttendanceHistory).toHaveBeenCalledWith(5, '2026-07-02', 'late');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/services/rollupService.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Create `src/services/rollupService.ts`**

```ts
import { AppError } from '../lib/errors.js';
import { getSessionConfigs, getSystemConfig } from './configService.js';
import { firstPingForUserInWindow } from '../db/queries/presenceQueries.js';
import { findByUserAndDate, upsertAttendanceHistory } from '../db/queries/attendanceHistoryQueries.js';
import { findUserById, listLearnerIds, UserRow } from '../db/queries/userQueries.js';
import { combineLocalDateAndTime } from './statusService.js';

function yesterdayInTz(now: Date, tz: string): string {
  const fmt = new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit' });
  const today = fmt.format(now); // YYYY-MM-DD
  const [y, m, d] = today.split('-').map((x) => Number.parseInt(x, 10));
  const dt = new Date(Date.UTC(y, m - 1, d));
  dt.setUTCDate(dt.getUTCDate() - 1);
  const yy = dt.getUTCFullYear();
  const mm = String(dt.getUTCMonth() + 1).padStart(2, '0');
  const dd = String(dt.getUTCDate()).padStart(2, '0');
  return `${yy}-${mm}-${dd}`;
}

export async function runRollup(input: {
  date?: string;
  userId?: number;
  now?: Date;
}): Promise<{ processed: number; skipped_leave: number }> {
  const now = input.now ?? new Date();
  const [{ AM, PM }, sys] = await Promise.all([getSessionConfigs(), getSystemConfig()]);
  const date = input.date ?? yesterdayInTz(now, sys.timezone);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new AppError('invalid_request', 'date must be YYYY-MM-DD');
  }

  const targets: number[] = input.userId !== undefined ? [input.userId] : await listLearnerIds();
  let processed = 0;
  let skipped_leave = 0;

  const dayStart = combineLocalDateAndTime(date, '00:00:00', sys.timezone);
  const dayEnd = new Date(dayStart.getTime() + 24 * 60 * 60 * 1000);

  for (const userId of targets) {
    const user: UserRow | null = await findUserById(userId);
    if (!user || user.role !== 'learner') continue;

    const existing = await findByUserAndDate(userId, date);
    if (existing?.status === 'leave') {
      skipped_leave++;
      continue;
    }

    const first = await firstPingForUserInWindow(userId, dayStart, dayEnd);
    const cfg = user.session === 'AM' ? AM : PM;
    const lateAfterUtc = combineLocalDateAndTime(date, cfg.late_after, sys.timezone);

    let status: 'early' | 'late' | 'absent';
    if (!first) status = 'absent';
    else if (first < lateAfterUtc) status = 'early';
    else status = 'late';

    await upsertAttendanceHistory(userId, date, status);
    processed++;
  }

  return { processed, skipped_leave };
}
```

- [ ] **Step 4: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/services/rollupService.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Aegis-Backend/src/services/rollupService.ts Aegis-Backend/tests/services/rollupService.test.ts
git commit -m "feat(rollup): add attendance rollup service"
```

---

## Task 12: rollup CLI script

**Files:**
- Create: `Aegis-Backend/scripts/rollupAttendance.ts`
- Modify: `Aegis-Backend/package.json` (add script)

**Interfaces:**
- Consumes: `runRollup` from rollupService; `logger`; `pool`
- Produces: `npm run rollup` invokes the script

- [ ] **Step 1: Create `scripts/rollupAttendance.ts`**

```ts
import 'dotenv/config';
import { logger } from '../src/lib/logger.js';
import { runRollup } from '../src/services/rollupService.js';
import { pool } from '../src/db/pool.js';

function parseArgs(): { date?: string; userId?: number } {
  const args = process.argv.slice(2);
  const out: { date?: string; userId?: number } = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--date') out.date = args[++i];
    else if (args[i] === '--user-id') out.userId = Number.parseInt(args[++i], 10);
  }
  return out;
}

async function main() {
  const opts = parseArgs();
  const result = await runRollup(opts);
  logger.info({ ...result, ...opts }, 'Rollup complete');
  await pool.end();
}

main().catch(async (err) => {
  logger.error({ err }, 'Rollup failed');
  await pool.end();
  process.exit(1);
});
```

- [ ] **Step 2: Add `"rollup"` script to `package.json`**

In `Aegis-Backend/package.json`, find the `"scripts"` object and add the `rollup` entry alongside `seed`:

Change:
```json
"seed": "tsx scripts/seed.ts",
```

to:
```json
"seed": "tsx scripts/seed.ts",
"rollup": "tsx scripts/rollupAttendance.ts",
```

- [ ] **Step 3: Type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add Aegis-Backend/scripts/rollupAttendance.ts Aegis-Backend/package.json
git commit -m "feat(rollup): add CLI wrapper (npm run rollup)"
```

---

## Task 13: Learner routes — /me, /dashboard, /histories, /beacons

**Files:**
- Create: `Aegis-Backend/src/routes/me.ts`
- Create: `Aegis-Backend/src/routes/dashboard.ts`
- Create: `Aegis-Backend/src/routes/histories.ts`
- Create: `Aegis-Backend/src/routes/beacons.ts`
- Create: `Aegis-Backend/tests/routes/learner.test.ts`

**Interfaces:**
- Consumes: `requireAuth`, `requireRole`; `findUserById`; `getLearnerDashboard` (dashboardService); `listHistoriesByUser`; `listAssignedDevices`
- Produces: four Express routers exported as `meRouter`, `dashboardRouter`, `historiesRouter`, `beaconsRouter`

- [ ] **Step 1: Write failing test `tests/routes/learner.test.ts`**

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
  findUserById: vi.fn(),
  findUserByUsername: vi.fn(),
  insertUser: vi.fn(),
  listLearners: vi.fn(),
  listLearnerIds: vi.fn(),
  countLearners: vi.fn(),
}));
vi.mock('../../src/db/queries/attendanceHistoryQueries.js', () => ({
  countByStatus: vi.fn(),
  findByUserAndDate: vi.fn(),
  upsertAttendanceHistory: vi.fn(),
  listHistoriesByUser: vi.fn(),
}));
vi.mock('../../src/db/queries/deviceQueries.js', () => ({
  listAssignedDevices: vi.fn(),
}));
vi.mock('../../src/services/dashboardService.js', () => ({
  getLearnerDashboard: vi.fn(),
  getAbsenceSummary: vi.fn(),
}));

const buildTestApp = async () => {
  const { errorHandler } = await import('../../src/middleware/errorHandler.js');
  const { meRouter } = await import('../../src/routes/me.js');
  const { dashboardRouter } = await import('../../src/routes/dashboard.js');
  const { historiesRouter } = await import('../../src/routes/histories.js');
  const { beaconsRouter } = await import('../../src/routes/beacons.js');
  const { signAccessToken } = await import('../../src/services/tokenService.js');
  const app = express();
  app.use(express.json());
  app.use('/api/v1/me', meRouter);
  app.use('/api/v1/dashboard', dashboardRouter);
  app.use('/api/v1/histories', historiesRouter);
  app.use('/api/v1/beacons', beaconsRouter);
  app.use(errorHandler);
  const token = signAccessToken({ sub: 42, role: 'learner', session: 'AM' });
  return { app, token };
};

beforeEach(() => vi.clearAllMocks());

describe('GET /me', () => {
  it('returns user profile', async () => {
    const { app, token } = await buildTestApp();
    const uq = await import('../../src/db/queries/userQueries.js');
    (uq.findUserById as any).mockResolvedValue({
      id_user: 42, username: 'alice', password: '', email: 'a@x', role: 'learner',
      first_name: 'Alice', last_name: 'Doe', session: 'AM',
    });
    const res = await request(app).get('/api/v1/me').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      id: 42, first_name: 'Alice', last_name: 'Doe', username: 'alice',
      email: 'a@x', role: 'learner', session: 'AM',
    });
  });

  it('rejects without auth', async () => {
    const { app } = await buildTestApp();
    const res = await request(app).get('/api/v1/me');
    expect(res.status).toBe(401);
  });
});

describe('GET /dashboard', () => {
  it('proxies to dashboardService', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/dashboardService.js');
    (svc.getLearnerDashboard as any).mockResolvedValue({
      total_attendance: 92, total_late: 7, leave_taken: 3, today_status: 'Checked In',
    });
    const res = await request(app).get('/api/v1/dashboard').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.today_status).toBe('Checked In');
  });
});

describe('GET /histories', () => {
  it('returns paged history', async () => {
    const { app, token } = await buildTestApp();
    const ah = await import('../../src/db/queries/attendanceHistoryQueries.js');
    (ah.listHistoriesByUser as any).mockResolvedValue({
      list: [{ id_user: 42, date: '2026-07-01', status: 'early' }],
      total: 1,
    });
    // presence queries return null so times are null
    const pq = await import('../../src/db/queries/presenceQueries.js').catch(() => null);
    if (pq) {
      // mock defensively (may not be loaded on this route)
    }
    const res = await request(app).get('/api/v1/histories?page=1&per_page=20').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.list[0].date).toBe('2026-07-01');
  });

  it('rejects month without year', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app).get('/api/v1/histories?month=7').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });
});

describe('GET /beacons', () => {
  it('returns assigned devices only', async () => {
    const { app, token } = await buildTestApp();
    const dq = await import('../../src/db/queries/deviceQueries.js');
    (dq.listAssignedDevices as any).mockResolvedValue([
      { id_device: 1, identifier: '1:2', id_room: 3, room_name: 'Lab' },
    ]);
    const res = await request(app).get('/api/v1/beacons').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.list).toEqual([
      { beacon_identifier: '1:2', room_id: 3, room_name: 'Lab' },
    ]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/routes/learner.test.ts`
Expected: FAIL — modules not found.

- [ ] **Step 3: Create `src/routes/me.ts`**

```ts
import { Router } from 'express';
import { requireAuth } from '../middleware/requireAuth.js';
import { requireRole } from '../middleware/requireRole.js';
import { findUserById } from '../db/queries/userQueries.js';
import { AppError } from '../lib/errors.js';

export const meRouter = Router();

meRouter.get('/', requireAuth, requireRole('learner'), async (req, res, next) => {
  try {
    const user = await findUserById(req.user!.id);
    if (!user) throw new AppError('not_found', 'User not found');
    res.json({
      id: user.id_user,
      first_name: user.first_name,
      last_name: user.last_name,
      username: user.username,
      email: user.email,
      role: user.role,
      session: user.session,
    });
  } catch (err) {
    next(err);
  }
});
```

- [ ] **Step 4: Create `src/routes/dashboard.ts`**

```ts
import { Router } from 'express';
import { requireAuth } from '../middleware/requireAuth.js';
import { requireRole } from '../middleware/requireRole.js';
import { getLearnerDashboard } from '../services/dashboardService.js';

export const dashboardRouter = Router();

dashboardRouter.get('/', requireAuth, requireRole('learner'), async (req, res, next) => {
  try {
    const result = await getLearnerDashboard(req.user!.id, new Date());
    res.json(result);
  } catch (err) {
    next(err);
  }
});
```

- [ ] **Step 5: Create `src/routes/histories.ts`**

```ts
import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../middleware/requireAuth.js';
import { requireRole } from '../middleware/requireRole.js';
import { AppError } from '../lib/errors.js';
import { listHistoriesByUser } from '../db/queries/attendanceHistoryQueries.js';
import { firstPingForUserInWindow, lastPingForUserInWindow } from '../db/queries/presenceQueries.js';
import { getSystemConfig } from '../services/configService.js';
import { combineLocalDateAndTime } from '../services/statusService.js';

const querySchema = z.object({
  month: z.coerce.number().int().min(1).max(12).optional(),
  year: z.coerce.number().int().min(1970).max(9999).optional(),
  page: z.coerce.number().int().min(1).default(1),
  per_page: z.coerce.number().int().min(1).max(100).default(20),
}).refine((v) => !(v.month !== undefined && v.year === undefined), {
  message: 'month requires year',
});

export const historiesRouter = Router();

historiesRouter.get('/', requireAuth, requireRole('learner'), async (req, res, next) => {
  const parsed = querySchema.safeParse(req.query);
  if (!parsed.success) return next(new AppError('invalid_request'));
  const { month, year, page, per_page } = parsed.data;
  try {
    const { list, total } = await listHistoriesByUser(req.user!.id, { month, year }, page, per_page);
    const sys = await getSystemConfig();
    const enriched = await Promise.all(list.map(async (row) => {
      const startUtc = combineLocalDateAndTime(row.date, '00:00:00', sys.timezone);
      const endUtc = new Date(startUtc.getTime() + 24 * 60 * 60 * 1000);
      const [first, last] = await Promise.all([
        firstPingForUserInWindow(req.user!.id, startUtc, endUtc),
        lastPingForUserInWindow(req.user!.id, startUtc, endUtc),
      ]);
      return {
        date: row.date,
        checked_in_at: first ? first.toISOString() : null,
        checked_out_at: last ? last.toISOString() : null,
        status: row.status,
      };
    }));
    res.json({ list: enriched, page, per_page, total });
  } catch (err) {
    next(err);
  }
});
```

- [ ] **Step 6: Create `src/routes/beacons.ts`**

```ts
import { Router } from 'express';
import { requireAuth } from '../middleware/requireAuth.js';
import { listAssignedDevices } from '../db/queries/deviceQueries.js';

export const beaconsRouter = Router();

beaconsRouter.get('/', requireAuth, async (_req, res, next) => {
  try {
    const rows = await listAssignedDevices();
    res.json({
      list: rows.map((r) => ({
        beacon_identifier: r.identifier,
        room_id: r.id_room,
        room_name: r.room_name,
      })),
    });
  } catch (err) {
    next(err);
  }
});
```

- [ ] **Step 7: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/routes/learner.test.ts`
Expected: PASS.

Note: the `/histories` test path calls `presenceQueries` — the mock is set at module load; add the mock declaration inline in the test file if needed. If the test fails to import `presenceQueries` mock, add this to the vi.mock block at the top of the test file:

```ts
vi.mock('../../src/db/queries/presenceQueries.js', () => ({
  insertPresenceLog: vi.fn(),
  firstPingForUserInWindow: vi.fn().mockResolvedValue(null),
  lastPingForUserInWindow: vi.fn().mockResolvedValue(null),
  firstAndLastPingBulk: vi.fn(),
  currentRoomPerUser: vi.fn(),
}));
vi.mock('../../src/services/configService.js', () => ({
  getSessionConfigs: vi.fn(),
  getSystemConfig: vi.fn().mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' }),
}));
```

- [ ] **Step 8: Commit**

```bash
git add Aegis-Backend/src/routes/me.ts Aegis-Backend/src/routes/dashboard.ts Aegis-Backend/src/routes/histories.ts Aegis-Backend/src/routes/beacons.ts Aegis-Backend/tests/routes/learner.test.ts
git commit -m "feat(routes): add learner routes /me /dashboard /histories /beacons"
```

---

## Task 14: Learner route — /presence

**Files:**
- Create: `Aegis-Backend/src/routes/presence.ts`
- Create: `Aegis-Backend/tests/routes/presence.test.ts`

**Interfaces:**
- Consumes: `requireAuth`, `requireRole`, `presenceRateLimit`, `recordPresence`
- Produces: `presenceRouter`

- [ ] **Step 1: Write failing test `tests/routes/presence.test.ts`**

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

vi.mock('../../src/services/presenceService.js', () => ({
  recordPresence: vi.fn(),
}));

const buildTestApp = async () => {
  const { errorHandler } = await import('../../src/middleware/errorHandler.js');
  const { presenceRouter } = await import('../../src/routes/presence.js');
  const { signAccessToken } = await import('../../src/services/tokenService.js');
  const app = express();
  app.use(express.json());
  app.use('/api/v1/presence', presenceRouter);
  app.use(errorHandler);
  const token = signAccessToken({ sub: 42, role: 'learner', session: 'AM' });
  return { app, token };
};

beforeEach(() => vi.clearAllMocks());

describe('POST /presence', () => {
  it('returns 204 on valid body', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/presenceService.js');
    (svc.recordPresence as any).mockResolvedValue(undefined);
    const res = await request(app)
      .post('/api/v1/presence')
      .set('Authorization', `Bearer ${token}`)
      .send({ room_id: 3, position_x: 1.5, position_y: 2.5, battery_level: 88 });
    expect(res.status).toBe(204);
    expect(svc.recordPresence).toHaveBeenCalledWith(42, {
      room_id: 3, position_x: 1.5, position_y: 2.5, battery_level: 88,
    });
  });

  it('rejects missing room_id', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .post('/api/v1/presence')
      .set('Authorization', `Bearer ${token}`)
      .send({});
    expect(res.status).toBe(400);
  });

  it('rejects battery_level out of range', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .post('/api/v1/presence')
      .set('Authorization', `Bearer ${token}`)
      .send({ room_id: 3, battery_level: 200 });
    expect(res.status).toBe(400);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/routes/presence.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Create `src/routes/presence.ts`**

```ts
import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../middleware/requireAuth.js';
import { requireRole } from '../middleware/requireRole.js';
import { presenceRateLimit } from '../middleware/presenceRateLimit.js';
import { AppError } from '../lib/errors.js';
import { recordPresence } from '../services/presenceService.js';

const bodySchema = z.object({
  room_id: z.number().int().positive(),
  position_x: z.number().optional(),
  position_y: z.number().optional(),
  battery_level: z.number().int().min(0).max(100).optional(),
});

export const presenceRouter = Router();

presenceRouter.post('/', requireAuth, requireRole('learner'), presenceRateLimit, async (req, res, next) => {
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    await recordPresence(req.user!.id, parsed.data);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});
```

- [ ] **Step 4: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/routes/presence.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Aegis-Backend/src/routes/presence.ts Aegis-Backend/tests/routes/presence.test.ts
git commit -m "feat(routes): add POST /presence with rate limit"
```

---

## Task 15: Admin routes — dashboard (absence-summary + overview)

**Files:**
- Create: `Aegis-Backend/src/routes/admin/absenceSummary.ts`
- Create: `Aegis-Backend/src/routes/admin/overview.ts`
- Create: `Aegis-Backend/tests/routes/adminDashboard.test.ts`

**Interfaces:**
- Consumes: `getAbsenceSummary`, `getOverview`
- Produces: `absenceSummaryRouter`, `adminOverviewRouter`

- [ ] **Step 1: Write failing test `tests/routes/adminDashboard.test.ts`**

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

vi.mock('../../src/services/dashboardService.js', () => ({
  getLearnerDashboard: vi.fn(),
  getAbsenceSummary: vi.fn(),
}));
vi.mock('../../src/services/overviewService.js', () => ({
  getOverview: vi.fn(),
}));

const buildTestApp = async (role: 'admin' | 'learner' = 'admin') => {
  const { errorHandler } = await import('../../src/middleware/errorHandler.js');
  const { absenceSummaryRouter } = await import('../../src/routes/admin/absenceSummary.js');
  const { adminOverviewRouter } = await import('../../src/routes/admin/overview.js');
  const { signAccessToken } = await import('../../src/services/tokenService.js');
  const app = express();
  app.use(express.json());
  app.use('/api/v1/admin/absence-summary', absenceSummaryRouter);
  app.use('/api/v1/admin/overview', adminOverviewRouter);
  app.use(errorHandler);
  const token = signAccessToken({ sub: 1, role });
  return { app, token };
};

beforeEach(() => vi.clearAllMocks());

describe('GET /admin/absence-summary', () => {
  it('returns counts', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/dashboardService.js');
    (svc.getAbsenceSummary as any).mockResolvedValue({
      present_summary: { on_time: 54, late_clock_in: 6 },
      absent_summary: { absent: 3, no_clock_in: 2 },
    });
    const res = await request(app).get('/api/v1/admin/absence-summary').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.present_summary.on_time).toBe(54);
  });

  it('rejects learner', async () => {
    const { app, token } = await buildTestApp('learner');
    const res = await request(app).get('/api/v1/admin/absence-summary').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(403);
  });
});

describe('GET /admin/overview', () => {
  it('proxies query params', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/overviewService.js');
    (svc.getOverview as any).mockResolvedValue({ list: [], page: 1, per_page: 20, total: 0 });
    const res = await request(app).get('/api/v1/admin/overview?name=Ali&session=AM').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(svc.getOverview).toHaveBeenCalledWith(expect.any(Date), { name: 'Ali', session: 'AM' }, 1, 20);
  });

  it('rejects invalid session', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app).get('/api/v1/admin/overview?session=XX').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/routes/adminDashboard.test.ts`
Expected: FAIL — modules not found.

- [ ] **Step 3: Create `src/routes/admin/absenceSummary.ts`**

```ts
import { Router } from 'express';
import { requireAuth } from '../../middleware/requireAuth.js';
import { requireRole } from '../../middleware/requireRole.js';
import { getAbsenceSummary } from '../../services/dashboardService.js';

export const absenceSummaryRouter = Router();

absenceSummaryRouter.get('/', requireAuth, requireRole('admin'), async (_req, res, next) => {
  try {
    const result = await getAbsenceSummary(new Date());
    res.json(result);
  } catch (err) {
    next(err);
  }
});
```

- [ ] **Step 4: Create `src/routes/admin/overview.ts`**

```ts
import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../middleware/requireAuth.js';
import { requireRole } from '../../middleware/requireRole.js';
import { AppError } from '../../lib/errors.js';
import { getOverview } from '../../services/overviewService.js';

const querySchema = z.object({
  name: z.string().max(100).optional(),
  session: z.enum(['AM', 'PM']).optional(),
  page: z.coerce.number().int().min(1).default(1),
  per_page: z.coerce.number().int().min(1).max(100).default(20),
});

export const adminOverviewRouter = Router();

adminOverviewRouter.get('/', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = querySchema.safeParse(req.query);
  if (!parsed.success) return next(new AppError('invalid_request'));
  const { name, session, page, per_page } = parsed.data;
  try {
    const result = await getOverview(new Date(), { name, session }, page, per_page);
    res.json(result);
  } catch (err) {
    next(err);
  }
});
```

- [ ] **Step 5: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/routes/adminDashboard.test.ts`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Aegis-Backend/src/routes/admin/absenceSummary.ts Aegis-Backend/src/routes/admin/overview.ts Aegis-Backend/tests/routes/adminDashboard.test.ts
git commit -m "feat(admin): add /admin/absence-summary and /admin/overview routes"
```

---

## Task 16: Admin routes — rooms + live radar

**Files:**
- Create: `Aegis-Backend/src/routes/admin/rooms.ts`
- Create: `Aegis-Backend/tests/routes/adminRooms.test.ts`

**Interfaces:**
- Consumes: `listAllRooms`, `getRoomMap`, `getRoomCurrentOccupants`, `getRoomAdditionalData`
- Produces: `adminRoomsRouter` (mounted at `/api/v1/admin/rooms`, includes nested `/:room_id/map`, `/:room_id/current-occupants`, `/:room_id/additional-data`)

- [ ] **Step 1: Write failing test `tests/routes/adminRooms.test.ts`**

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

vi.mock('../../src/services/roomsService.js', () => ({
  listAllRooms: vi.fn(),
  getRoomMap: vi.fn(),
  getRoomCurrentOccupants: vi.fn(),
  getRoomAdditionalData: vi.fn(),
}));

const buildTestApp = async () => {
  const { errorHandler } = await import('../../src/middleware/errorHandler.js');
  const { adminRoomsRouter } = await import('../../src/routes/admin/rooms.js');
  const { signAccessToken } = await import('../../src/services/tokenService.js');
  const app = express();
  app.use(express.json());
  app.use('/api/v1/admin/rooms', adminRoomsRouter);
  app.use(errorHandler);
  const token = signAccessToken({ sub: 1, role: 'admin' });
  return { app, token };
};

beforeEach(() => vi.clearAllMocks());

describe('GET /admin/rooms', () => {
  it('returns list', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/roomsService.js');
    (svc.listAllRooms as any).mockResolvedValue([{ id: 1, name: 'Lab A' }]);
    const res = await request(app).get('/api/v1/admin/rooms').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.list).toHaveLength(1);
  });
});

describe('GET /admin/rooms/:id/map', () => {
  it('returns 404 when room missing', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/roomsService.js');
    const { AppError } = await import('../../src/lib/errors.js');
    (svc.getRoomMap as any).mockRejectedValue(new AppError('not_found'));
    const res = await request(app).get('/api/v1/admin/rooms/99/map').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });

  it('rejects invalid id', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app).get('/api/v1/admin/rooms/abc/map').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });
});

describe('GET /admin/rooms/:id/current-occupants', () => {
  it('returns list', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/roomsService.js');
    (svc.getRoomCurrentOccupants as any).mockResolvedValue({ list: [] });
    const res = await request(app).get('/api/v1/admin/rooms/1/current-occupants').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
  });
});

describe('GET /admin/rooms/:id/additional-data', () => {
  it('returns readings', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/roomsService.js');
    (svc.getRoomAdditionalData as any).mockResolvedValue({ room_temperature: 24.5, humidity: 62, people_in_room: 3 });
    const res = await request(app).get('/api/v1/admin/rooms/1/additional-data').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.room_temperature).toBe(24.5);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/routes/adminRooms.test.ts`
Expected: FAIL.

- [ ] **Step 3: Create `src/routes/admin/rooms.ts`**

```ts
import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../middleware/requireAuth.js';
import { requireRole } from '../../middleware/requireRole.js';
import { AppError } from '../../lib/errors.js';
import {
  listAllRooms,
  getRoomMap,
  getRoomCurrentOccupants,
  getRoomAdditionalData,
} from '../../services/roomsService.js';

const idParam = z.object({ room_id: z.coerce.number().int().positive() });

export const adminRoomsRouter = Router();

adminRoomsRouter.get('/', requireAuth, requireRole('admin'), async (_req, res, next) => {
  try {
    const rows = await listAllRooms();
    res.json({ list: rows });
  } catch (err) {
    next(err);
  }
});

adminRoomsRouter.get('/:room_id/map', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = idParam.safeParse(req.params);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    const result = await getRoomMap(parsed.data.room_id, new Date());
    res.json(result);
  } catch (err) {
    next(err);
  }
});

adminRoomsRouter.get('/:room_id/current-occupants', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = idParam.safeParse(req.params);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    const result = await getRoomCurrentOccupants(parsed.data.room_id, new Date());
    res.json(result);
  } catch (err) {
    next(err);
  }
});

adminRoomsRouter.get('/:room_id/additional-data', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = idParam.safeParse(req.params);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    const result = await getRoomAdditionalData(parsed.data.room_id, new Date());
    res.json(result);
  } catch (err) {
    next(err);
  }
});
```

- [ ] **Step 4: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/routes/adminRooms.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Aegis-Backend/src/routes/admin/rooms.ts Aegis-Backend/tests/routes/adminRooms.test.ts
git commit -m "feat(admin): add /admin/rooms and nested live radar routes"
```

---

## Task 17: Admin routes — config (session + system)

**Files:**
- Create: `Aegis-Backend/src/routes/admin/sessionConfig.ts`
- Create: `Aegis-Backend/src/routes/admin/systemConfig.ts`
- Create: `Aegis-Backend/tests/routes/adminConfig.test.ts`

**Interfaces:**
- Consumes: `getSessionConfigs`, `updateSessionConfig`, `getSystemConfig`, `updateSystemConfig` from configService
- Produces: `sessionConfigRouter`, `systemConfigRouter`

- [ ] **Step 1: Write failing test `tests/routes/adminConfig.test.ts`**

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

vi.mock('../../src/services/configService.js', () => ({
  getSessionConfigs: vi.fn(),
  updateSessionConfig: vi.fn(),
  getSystemConfig: vi.fn(),
  updateSystemConfig: vi.fn(),
  invalidateConfigCache: vi.fn(),
}));

const buildTestApp = async () => {
  const { errorHandler } = await import('../../src/middleware/errorHandler.js');
  const { sessionConfigRouter } = await import('../../src/routes/admin/sessionConfig.js');
  const { systemConfigRouter } = await import('../../src/routes/admin/systemConfig.js');
  const { signAccessToken } = await import('../../src/services/tokenService.js');
  const app = express();
  app.use(express.json());
  app.use('/api/v1/admin/session-config', sessionConfigRouter);
  app.use('/api/v1/admin/system-config', systemConfigRouter);
  app.use(errorHandler);
  const token = signAccessToken({ sub: 1, role: 'admin' });
  return { app, token };
};

beforeEach(() => vi.clearAllMocks());

describe('session-config', () => {
  it('GET returns AM+PM', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/configService.js');
    (svc.getSessionConfigs as any).mockResolvedValue({
      AM: { session: 'AM', start_time: '08:00:00', late_after: '08:15:00', end_time: '12:00:00' },
      PM: { session: 'PM', start_time: '13:00:00', late_after: '13:15:00', end_time: '17:00:00' },
    });
    const res = await request(app).get('/api/v1/admin/session-config').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.AM.start_time).toBe('08:00:00');
  });

  it('PUT /:session validates body', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app).put('/api/v1/admin/session-config/AM')
      .set('Authorization', `Bearer ${token}`)
      .send({ start_time: '08:00', late_after: '08:15:00', end_time: '12:00:00' });
    expect(res.status).toBe(400);
  });

  it('PUT /:session returns 204', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/configService.js');
    (svc.updateSessionConfig as any).mockResolvedValue(undefined);
    const res = await request(app).put('/api/v1/admin/session-config/AM')
      .set('Authorization', `Bearer ${token}`)
      .send({ start_time: '08:00:00', late_after: '08:15:00', end_time: '12:00:00' });
    expect(res.status).toBe(204);
  });
});

describe('system-config', () => {
  it('GET returns settings', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/configService.js');
    (svc.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' });
    const res = await request(app).get('/api/v1/admin/system-config').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.presence_staleness_minutes).toBe(5);
  });

  it('PUT accepts partial update', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/configService.js');
    (svc.updateSystemConfig as any).mockResolvedValue(undefined);
    const res = await request(app).put('/api/v1/admin/system-config')
      .set('Authorization', `Bearer ${token}`)
      .send({ timezone: 'Asia/Jakarta' });
    expect(res.status).toBe(204);
    expect(svc.updateSystemConfig).toHaveBeenCalledWith({ timezone: 'Asia/Jakarta' });
  });

  it('PUT rejects unknown fields', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app).put('/api/v1/admin/system-config')
      .set('Authorization', `Bearer ${token}`)
      .send({ unknown_key: 'x' });
    expect(res.status).toBe(400);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/routes/adminConfig.test.ts`
Expected: FAIL.

- [ ] **Step 3: Create `src/routes/admin/sessionConfig.ts`**

```ts
import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../middleware/requireAuth.js';
import { requireRole } from '../../middleware/requireRole.js';
import { AppError } from '../../lib/errors.js';
import { getSessionConfigs, updateSessionConfig } from '../../services/configService.js';

const timePattern = /^([01]\d|2[0-3]):[0-5]\d:[0-5]\d$/;
const bodySchema = z.object({
  start_time: z.string().regex(timePattern),
  late_after: z.string().regex(timePattern),
  end_time: z.string().regex(timePattern),
});
const paramSchema = z.object({ session: z.enum(['AM', 'PM']) });

export const sessionConfigRouter = Router();

sessionConfigRouter.get('/', requireAuth, requireRole('admin'), async (_req, res, next) => {
  try {
    const cfgs = await getSessionConfigs();
    res.json({
      AM: { start_time: cfgs.AM.start_time, late_after: cfgs.AM.late_after, end_time: cfgs.AM.end_time },
      PM: { start_time: cfgs.PM.start_time, late_after: cfgs.PM.late_after, end_time: cfgs.PM.end_time },
    });
  } catch (err) {
    next(err);
  }
});

sessionConfigRouter.put('/:session', requireAuth, requireRole('admin'), async (req, res, next) => {
  const p = paramSchema.safeParse(req.params);
  const b = bodySchema.safeParse(req.body);
  if (!p.success || !b.success) return next(new AppError('invalid_request'));
  try {
    await updateSessionConfig(p.data.session, b.data);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});
```

- [ ] **Step 4: Create `src/routes/admin/systemConfig.ts`**

```ts
import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../middleware/requireAuth.js';
import { requireRole } from '../../middleware/requireRole.js';
import { AppError } from '../../lib/errors.js';
import { getSystemConfig, updateSystemConfig } from '../../services/configService.js';

const bodySchema = z.object({
  presence_staleness_minutes: z.number().int().min(1).max(60).optional(),
  timezone: z.string().min(1).max(64).optional(),
}).strict();

export const systemConfigRouter = Router();

systemConfigRouter.get('/', requireAuth, requireRole('admin'), async (_req, res, next) => {
  try {
    const cfg = await getSystemConfig();
    res.json(cfg);
  } catch (err) {
    next(err);
  }
});

systemConfigRouter.put('/', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    await updateSystemConfig(parsed.data);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});
```

- [ ] **Step 5: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/routes/adminConfig.test.ts`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Aegis-Backend/src/routes/admin/sessionConfig.ts Aegis-Backend/src/routes/admin/systemConfig.ts Aegis-Backend/tests/routes/adminConfig.test.ts
git commit -m "feat(admin): add /admin/session-config and /admin/system-config routes"
```

---

## Task 18: Admin route — /rollup

**Files:**
- Create: `Aegis-Backend/src/routes/admin/rollup.ts`
- Create: `Aegis-Backend/tests/routes/adminRollup.test.ts`

**Interfaces:**
- Consumes: `runRollup`
- Produces: `rollupRouter`

- [ ] **Step 1: Write failing test `tests/routes/adminRollup.test.ts`**

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

vi.mock('../../src/services/rollupService.js', () => ({
  runRollup: vi.fn(),
}));

const buildTestApp = async () => {
  const { errorHandler } = await import('../../src/middleware/errorHandler.js');
  const { rollupRouter } = await import('../../src/routes/admin/rollup.js');
  const { signAccessToken } = await import('../../src/services/tokenService.js');
  const app = express();
  app.use(express.json());
  app.use('/api/v1/admin/rollup', rollupRouter);
  app.use(errorHandler);
  const token = signAccessToken({ sub: 1, role: 'admin' });
  return { app, token };
};

beforeEach(() => vi.clearAllMocks());

describe('POST /admin/rollup', () => {
  it('returns processed and skipped_leave', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/rollupService.js');
    (svc.runRollup as any).mockResolvedValue({ processed: 60, skipped_leave: 2 });
    const res = await request(app).post('/api/v1/admin/rollup').set('Authorization', `Bearer ${token}`).send({});
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ processed: 60, skipped_leave: 2 });
  });

  it('rejects invalid date format', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app).post('/api/v1/admin/rollup').set('Authorization', `Bearer ${token}`).send({ date: 'bad' });
    expect(res.status).toBe(400);
  });

  it('passes user_id through', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/rollupService.js');
    (svc.runRollup as any).mockResolvedValue({ processed: 1, skipped_leave: 0 });
    const res = await request(app).post('/api/v1/admin/rollup').set('Authorization', `Bearer ${token}`).send({ user_id: 5 });
    expect(res.status).toBe(200);
    expect(svc.runRollup).toHaveBeenCalledWith({ userId: 5 });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/routes/adminRollup.test.ts`
Expected: FAIL.

- [ ] **Step 3: Create `src/routes/admin/rollup.ts`**

```ts
import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../middleware/requireAuth.js';
import { requireRole } from '../../middleware/requireRole.js';
import { AppError } from '../../lib/errors.js';
import { runRollup } from '../../services/rollupService.js';

const bodySchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  user_id: z.number().int().positive().optional(),
}).strict();

export const rollupRouter = Router();

rollupRouter.post('/', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = bodySchema.safeParse(req.body ?? {});
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    const result = await runRollup({ date: parsed.data.date, userId: parsed.data.user_id });
    res.json(result);
  } catch (err) {
    next(err);
  }
});
```

- [ ] **Step 4: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/routes/adminRollup.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```ts
git add Aegis-Backend/src/routes/admin/rollup.ts Aegis-Backend/tests/routes/adminRollup.test.ts
git commit -m "feat(admin): add POST /admin/rollup endpoint"
```

---

## Task 19: Mount all new routers in app.ts

**Files:**
- Modify: `Aegis-Backend/src/app.ts`

**Interfaces:**
- Consumes: every router created in Tasks 13–18
- Produces: `buildApp()` now mounts the full API surface

- [ ] **Step 1: Update `src/app.ts`**

Rewrite the file to mount all routers:

```ts
import express from 'express';
import { authRouter } from './routes/auth.js';
import { meRouter } from './routes/me.js';
import { dashboardRouter } from './routes/dashboard.js';
import { historiesRouter } from './routes/histories.js';
import { presenceRouter } from './routes/presence.js';
import { beaconsRouter } from './routes/beacons.js';
import { absenceSummaryRouter } from './routes/admin/absenceSummary.js';
import { adminOverviewRouter } from './routes/admin/overview.js';
import { adminRoomsRouter } from './routes/admin/rooms.js';
import { sessionConfigRouter } from './routes/admin/sessionConfig.js';
import { systemConfigRouter } from './routes/admin/systemConfig.js';
import { rollupRouter } from './routes/admin/rollup.js';
import { errorHandler } from './middleware/errorHandler.js';

export function buildApp(): express.Express {
  const app = express();
  app.set('trust proxy', 1);
  app.use(express.json({ limit: '64kb' }));

  app.get('/health', (_req, res) => {
    res.json({ status: 'ok' });
  });

  app.use('/auth', authRouter);

  app.use('/api/v1/me', meRouter);
  app.use('/api/v1/dashboard', dashboardRouter);
  app.use('/api/v1/histories', historiesRouter);
  app.use('/api/v1/presence', presenceRouter);
  app.use('/api/v1/beacons', beaconsRouter);

  app.use('/api/v1/admin/absence-summary', absenceSummaryRouter);
  app.use('/api/v1/admin/overview', adminOverviewRouter);
  app.use('/api/v1/admin/rooms', adminRoomsRouter);
  app.use('/api/v1/admin/session-config', sessionConfigRouter);
  app.use('/api/v1/admin/system-config', systemConfigRouter);
  app.use('/api/v1/admin/rollup', rollupRouter);

  app.use(errorHandler);
  return app;
}
```

- [ ] **Step 2: Type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 3: Full test suite**

Run: `cd Aegis-Backend && npm test`
Expected: all suites pass. Test count should be roughly 32 (auth) + 8 (config) + 12 (status) + 3 (presence) + 2 (dashboard) + 1 (overview) + 4 (rooms) + 2 (rollup) + 6 (learner routes) + 3 (presence route) + 4 (adminDashboard) + 4 (adminRooms) + 5 (adminConfig) + 3 (adminRollup) = 89.

- [ ] **Step 4: Lint**

Run: `cd Aegis-Backend && npm run lint`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add Aegis-Backend/src/app.ts
git commit -m "feat(app): mount attendance API routers and health"
```

---

## Task 20: Final integration checks

**Files:** none new; verification only.

- [ ] **Step 1: Full type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 2: Full test suite**

Run: `cd Aegis-Backend && npm test`
Expected: all tests pass (approximately 89).

- [ ] **Step 3: Lint**

Run: `cd Aegis-Backend && npm run lint`
Expected: exit 0.

- [ ] **Step 4: Confirm rollup script is invocable**

Run: `cd Aegis-Backend && npm run rollup -- --date 2000-01-01 2>&1 | head -5`
Expected: fails cleanly with a DB connection error (no MySQL in test env), but the CLI parser and imports resolved.

- [ ] **Step 5: Commit** (optional, if any lint auto-fixes were applied — otherwise skip)

---

## Verification checklist (post-implementation)

- `npm test` passes. Suites: config, statusService, dashboardService, overviewService, roomsService, rollupService, presenceService, plus all route tests.
- `npm run build` compiles cleanly.
- `npm run migrate` applied to an empty MySQL creates `SESSION_CONFIG` and `SYSTEM_CONFIG` with defaults.
- `npm run seed` still works.
- `npm run rollup` runs against MySQL and rolls up yesterday for all learners.
- `GET /health`, `POST /auth/login`, and each of the 16 new endpoints respond as documented in the API reference.
- Concurrent PUTs on `/admin/session-config/AM` and reads via `/admin/session-config` see the new values within 30 s (immediate cache invalidation).
- Presence rate limit of 20/minute per learner enforced.
