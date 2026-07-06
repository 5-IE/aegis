# Aegis Admin User CRUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build 7 admin-only user management endpoints (list, get, create, update, reset password, soft delete, reactivate) with an `is_active` soft-delete column added to the `USER` table.

**Architecture:** Follows the established layering — routes → services → queries. New `userService.ts` owns write-side business logic (uniqueness enforcement, self-delete + last-admin safeguards, refresh-token revocation on delete/password-reset). Existing user-facing queries filter by `is_active = TRUE` so soft-deleted users can't log in or appear in learner-facing views.

**Tech Stack:** Same as prior features — Node.js 20 + TypeScript strict + Express 4 + mysql2/promise + bcrypt + zod + pino + Vitest + supertest.

## Global Constraints

- TypeScript strict mode; ES modules (`"type": "module"`).
- DB access lives only in `src/db/*`.
- Every route: `requireAuth` + `requireRole('admin')`.
- Every service ships with a unit test that mocks the DB query layer.
- Error response shape: `{ "error": "<code>", "message": "<human text>" }`.
- Error codes and status: `invalid_request` 400, `unauthorized` 401, `forbidden` 403, `not_found` 404, **`conflict` 409 (NEW)**, `too_many_requests` 429, `internal_error` 500.
- Response bodies use `snake_case`.
- Password bcrypt cost factor 12; passwords capped at 72 chars (bcrypt limit).
- Response shape for user (used everywhere): `{ id, username, email, role, session, first_name, last_name, is_active, created_at }`. Never includes `password`.
- All `TIMESTAMP` values are UTC (already true).
- Soft delete semantics:
  - `is_active = FALSE` blocks login (via `findUserByUsername` filter).
  - Delete also revokes all refresh tokens for the target user.
  - Delete blocks self-delete (400) and last-admin-delete (400).
- Uniqueness rules:
  - `username` — unique across ALL users (active + inactive).
  - `email` — unique across ACTIVE users only.
- `PATCH` cannot change `username`, `password`, or `is_active` (use dedicated endpoints for the latter two; recreate for username).

---

## File Structure

**Created — migration:**
- `Aegis-Backend/migrations/0006_user_is_active.sql`

**Created — service:**
- `Aegis-Backend/src/services/userService.ts`

**Created — route:**
- `Aegis-Backend/src/routes/admin/users.ts`

**Created — tests:**
- `Aegis-Backend/tests/services/userService.test.ts`
- `Aegis-Backend/tests/routes/adminUsers.test.ts`

**Modified — errors:**
- `Aegis-Backend/src/lib/errors.ts` — add `'conflict'` error code (409)

**Modified — DB queries:**
- `Aegis-Backend/src/db/queries/userQueries.ts` — add `is_active` field to `UserRow`; add `is_active = TRUE` filter to `findUserByUsername`, `findUserById`, `listLearners`, `listLearnerIds`, `countLearners`; add new functions `findUserByEmailActive`, `listUsers`, `updateUser`, `updateUserPassword`, `softDeleteUser`, `reactivateUser`, `countActiveAdmins`.

**Modified — app wiring:**
- `Aegis-Backend/src/app.ts` — mount `usersRouter` at `/api/v1/admin/users`.

---

## Task 1: Migration 0006 — add `is_active` column

**Files:**
- Create: `Aegis-Backend/migrations/0006_user_is_active.sql`

**Interfaces:**
- Consumes: existing `USER` table
- Produces: `USER.is_active` column (BOOLEAN NOT NULL DEFAULT TRUE) + index

- [ ] **Step 1: Create the migration file**

```sql
USE `AEGIS`;

ALTER TABLE `USER`
  ADD COLUMN `is_active` BOOLEAN NOT NULL DEFAULT TRUE;

CREATE INDEX `idx_user_active` ON `USER` (`is_active`);
```

Path: `Aegis-Backend/migrations/0006_user_is_active.sql`

- [ ] **Step 2: Commit**

```bash
cd /Users/workspace/Documents/personal/fiveie/aegis/.claude/worktrees/jazzy-humming-sphinx
git add Aegis-Backend/migrations/0006_user_is_active.sql
git commit -m "feat(db): add is_active column to USER for soft delete"
```

No tests in this task (SQL migration; no MySQL server available in this environment). Migration will be exercised end-to-end when a fresh DB is bootstrapped.

---

## Task 2: Add `conflict` error code

**Files:**
- Modify: `Aegis-Backend/src/lib/errors.ts`

**Interfaces:**
- Consumes: existing `AppError`, `ErrorCode`
- Produces: `AppError` now accepts `'conflict'` code with status 409

- [ ] **Step 1: Read the current file**

Run: `cat Aegis-Backend/src/lib/errors.ts`
Confirm the three shapes: `ErrorCode` union, `STATUS` map, `DEFAULT_MESSAGE` map.

- [ ] **Step 2: Add `'conflict'` to the `ErrorCode` union**

In `src/lib/errors.ts`, change:

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

to:

```ts
export type ErrorCode =
  | 'invalid_request'
  | 'invalid_credentials'
  | 'invalid_grant'
  | 'unauthorized'
  | 'forbidden'
  | 'not_found'
  | 'conflict'
  | 'too_many_requests'
  | 'internal_error';
```

- [ ] **Step 3: Add `conflict: 409` to STATUS map**

Insert into the STATUS object, right after `not_found: 404`:

```ts
  conflict: 409,
```

- [ ] **Step 4: Add message to DEFAULT_MESSAGE map**

Insert into the DEFAULT_MESSAGE object, right after `not_found`:

```ts
  conflict: 'The resource already exists',
```

- [ ] **Step 5: Run full test suite (verify no regression)**

Run: `cd Aegis-Backend && npm test`
Expected: all existing tests pass. Baseline count depends on branch state — should be around 102 on top of main.

- [ ] **Step 6: Type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
cd /Users/workspace/Documents/personal/fiveie/aegis/.claude/worktrees/jazzy-humming-sphinx
git add Aegis-Backend/src/lib/errors.ts
git commit -m "feat(errors): add conflict error code (409)"
```

---

## Task 3: Extend `userQueries.ts` — is_active field + filters + new functions

**Files:**
- Modify: `Aegis-Backend/src/db/queries/userQueries.ts`

**Interfaces:**
- Consumes: `pool` from `src/db/pool.ts`
- Produces:
  - `UserRow` now includes `is_active: boolean` and `created_at: Date`
  - `findUserByUsername(username)`: filters `is_active = TRUE`
  - `findUserById(id)`: filters `is_active = TRUE`
  - `listLearners(...)`: filters `is_active = TRUE`
  - `listLearnerIds()`: filters `is_active = TRUE`
  - `countLearners()`: filters `is_active = TRUE`
  - New: `async function findUserByIdAnyState(id: number): Promise<UserRow | null>` — bypasses is_active filter for admin views
  - New: `async function findUserByUsernameAnyState(username: string): Promise<UserRow | null>` — for uniqueness check
  - New: `async function findUserByEmailActive(email: string): Promise<UserRow | null>` — for uniqueness check among active users only
  - New: `async function listUsers(filter: { role?: 'admin' | 'learner'; session?: 'AM' | 'PM'; name?: string; includeInactive?: boolean }, page: number, perPage: number): Promise<{ list: UserRow[]; total: number }>`
  - New: `async function updateUserFields(id: number, patch: { email?: string; role?: 'admin' | 'learner'; session?: 'AM' | 'PM'; first_name?: string | null; last_name?: string | null }): Promise<void>`
  - New: `async function updateUserPassword(id: number, passwordHash: string): Promise<void>`
  - New: `async function softDeleteUser(id: number): Promise<void>`
  - New: `async function reactivateUser(id: number): Promise<void>`
  - New: `async function countActiveAdmins(): Promise<number>`

- [ ] **Step 1: Replace the file with the extended version**

Overwrite `Aegis-Backend/src/db/queries/userQueries.ts` with the following complete contents:

```ts
import { RowDataPacket, ResultSetHeader } from 'mysql2';
import { pool } from '../pool.js';

export interface UserRow {
  id_user: number;
  username: string;
  password: string;
  email: string;
  role: 'admin' | 'learner';
  first_name: string | null;
  last_name: string | null;
  session: 'AM' | 'PM';
  is_active: boolean;
  created_at: Date;
}

export async function findUserByUsername(username: string): Promise<UserRow | null> {
  const [rows] = await pool.query<(UserRow & RowDataPacket)[]>(
    'SELECT * FROM `USER` WHERE `username` = ? AND `is_active` = TRUE LIMIT 1',
    [username],
  );
  return rows[0] ?? null;
}

export async function findUserByUsernameAnyState(username: string): Promise<UserRow | null> {
  const [rows] = await pool.query<(UserRow & RowDataPacket)[]>(
    'SELECT * FROM `USER` WHERE `username` = ? LIMIT 1',
    [username],
  );
  return rows[0] ?? null;
}

export async function findUserById(id: number): Promise<UserRow | null> {
  const [rows] = await pool.query<(UserRow & RowDataPacket)[]>(
    'SELECT * FROM `USER` WHERE `id_user` = ? AND `is_active` = TRUE LIMIT 1',
    [id],
  );
  return rows[0] ?? null;
}

export async function findUserByIdAnyState(id: number): Promise<UserRow | null> {
  const [rows] = await pool.query<(UserRow & RowDataPacket)[]>(
    'SELECT * FROM `USER` WHERE `id_user` = ? LIMIT 1',
    [id],
  );
  return rows[0] ?? null;
}

export async function findUserByEmailActive(email: string): Promise<UserRow | null> {
  const [rows] = await pool.query<(UserRow & RowDataPacket)[]>(
    'SELECT * FROM `USER` WHERE `email` = ? AND `is_active` = TRUE LIMIT 1',
    [email],
  );
  return rows[0] ?? null;
}

export async function insertUser(input: {
  username: string;
  passwordHash: string;
  email: string;
  role: 'admin' | 'learner';
  firstName?: string;
  lastName?: string;
  session?: 'AM' | 'PM';
}): Promise<number> {
  const [result] = await pool.query<ResultSetHeader>(
    `INSERT INTO \`USER\`
       (\`username\`, \`password\`, \`email\`, \`role\`, \`first_name\`, \`last_name\`, \`session\`)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    [
      input.username,
      input.passwordHash,
      input.email,
      input.role,
      input.firstName ?? null,
      input.lastName ?? null,
      input.session ?? 'AM',
    ],
  );
  return result.insertId;
}

export async function listLearners(
  filter: { name?: string; session?: 'AM' | 'PM' },
  page: number,
  perPage: number,
): Promise<{ list: UserRow[]; total: number }> {
  const conds: string[] = [`\`role\` = 'learner'`, '`is_active` = TRUE'];
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
    "SELECT `id_user` FROM `USER` WHERE `role` = 'learner' AND `is_active` = TRUE",
  );
  return rows.map((r) => r.id_user);
}

export async function countLearners(): Promise<number> {
  const [rows] = await pool.query<({ c: number } & RowDataPacket)[]>(
    "SELECT COUNT(*) AS c FROM `USER` WHERE `role` = 'learner' AND `is_active` = TRUE",
  );
  return rows[0]?.c ?? 0;
}

export async function listUsers(
  filter: { role?: 'admin' | 'learner'; session?: 'AM' | 'PM'; name?: string; includeInactive?: boolean },
  page: number,
  perPage: number,
): Promise<{ list: UserRow[]; total: number }> {
  const conds: string[] = [];
  const params: unknown[] = [];
  if (!filter.includeInactive) {
    conds.push('`is_active` = TRUE');
  }
  if (filter.role !== undefined) {
    conds.push('`role` = ?');
    params.push(filter.role);
  }
  if (filter.session !== undefined) {
    conds.push('`session` = ?');
    params.push(filter.session);
  }
  if (filter.name !== undefined && filter.name !== '') {
    conds.push(`TRIM(CONCAT_WS(' ', \`first_name\`, \`last_name\`)) LIKE ?`);
    params.push(`%${filter.name}%`);
  }
  const where = conds.length > 0 ? 'WHERE ' + conds.join(' AND ') : '';

  const [countRows] = await pool.query<({ c: number } & RowDataPacket)[]>(
    `SELECT COUNT(*) AS c FROM \`USER\` ${where}`,
    params,
  );
  const total = countRows[0]?.c ?? 0;

  const offset = (page - 1) * perPage;
  const [rows] = await pool.query<(UserRow & RowDataPacket)[]>(
    `SELECT * FROM \`USER\` ${where}
     ORDER BY \`first_name\` ASC, \`last_name\` ASC, \`id_user\` ASC
     LIMIT ? OFFSET ?`,
    [...params, perPage, offset],
  );
  return { list: rows, total };
}

export async function updateUserFields(
  id: number,
  patch: {
    email?: string;
    role?: 'admin' | 'learner';
    session?: 'AM' | 'PM';
    first_name?: string | null;
    last_name?: string | null;
  },
): Promise<void> {
  const sets: string[] = [];
  const params: unknown[] = [];
  if (patch.email !== undefined) {
    sets.push('`email` = ?');
    params.push(patch.email);
  }
  if (patch.role !== undefined) {
    sets.push('`role` = ?');
    params.push(patch.role);
  }
  if (patch.session !== undefined) {
    sets.push('`session` = ?');
    params.push(patch.session);
  }
  if (patch.first_name !== undefined) {
    sets.push('`first_name` = ?');
    params.push(patch.first_name);
  }
  if (patch.last_name !== undefined) {
    sets.push('`last_name` = ?');
    params.push(patch.last_name);
  }
  if (sets.length === 0) return;
  params.push(id);
  await pool.query(
    `UPDATE \`USER\` SET ${sets.join(', ')} WHERE \`id_user\` = ?`,
    params,
  );
}

export async function updateUserPassword(id: number, passwordHash: string): Promise<void> {
  await pool.query(
    'UPDATE `USER` SET `password` = ? WHERE `id_user` = ?',
    [passwordHash, id],
  );
}

export async function softDeleteUser(id: number): Promise<void> {
  await pool.query(
    'UPDATE `USER` SET `is_active` = FALSE WHERE `id_user` = ?',
    [id],
  );
}

export async function reactivateUser(id: number): Promise<void> {
  await pool.query(
    'UPDATE `USER` SET `is_active` = TRUE WHERE `id_user` = ?',
    [id],
  );
}

export async function countActiveAdmins(): Promise<number> {
  const [rows] = await pool.query<({ c: number } & RowDataPacket)[]>(
    "SELECT COUNT(*) AS c FROM `USER` WHERE `role` = 'admin' AND `is_active` = TRUE",
  );
  return rows[0]?.c ?? 0;
}
```

- [ ] **Step 2: Type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 3: Run full test suite (existing tests must still pass)**

Run: `cd Aegis-Backend && npm test`
Expected: all existing tests pass. Some tests mock `findUserByUsername` / `findUserById` etc. — those mocks provide a `UserRow` fixture that does NOT currently include `is_active` and `created_at`. That's fine: since the mocks bypass the DB, the extra columns aren't read; TypeScript accepts the mocked value as `Promise<UserRow>` because the mock is typed `as any` in the existing test files. If any existing test fails, check whether the mock's returned object needs the new fields — but this should not happen due to the `as any` cast idiom.

Note: `existing/auth`, `dashboard`, `overview`, `histories`, `me`, `presence`, `rooms`, `rollup` service tests mock queries. They should all still pass unchanged. If a specific test fails with `is_active` missing, fix that test file by adding `is_active: true, created_at: new Date()` to the mocked user object — a minimal, targeted change.

- [ ] **Step 4: Commit**

```bash
git add Aegis-Backend/src/db/queries/userQueries.ts
git commit -m "feat(db): extend userQueries with is_active filter + user CRUD helpers"
```

---

## Task 4: `userService.ts` — orchestration

**Files:**
- Create: `Aegis-Backend/src/services/userService.ts`
- Create: `Aegis-Backend/tests/services/userService.test.ts`

**Interfaces:**
- Consumes:
  - `hashPassword` from `passwordService`
  - `revokeAllRefreshTokensForUser` from `refreshTokenQueries`
  - All new/modified functions from `userQueries` (Task 3)
  - `AppError` from `errors`
- Produces:
  - `interface PublicUser { id: number; username: string; email: string; role: 'admin' | 'learner'; session: 'AM' | 'PM'; first_name: string | null; last_name: string | null; is_active: boolean; created_at: string }` — `created_at` is ISO 8601 string in the public shape.
  - `function toPublicUser(row: UserRow): PublicUser`
  - `async function listUsersService(filter, page, perPage): Promise<{ list: PublicUser[]; total: number; page: number; per_page: number }>`
  - `async function getUserService(id: number): Promise<PublicUser>` — throws `not_found`
  - `async function createUserService(input): Promise<PublicUser>` — throws `invalid_request` (missing session for learner), `conflict` (username exists any state, or email exists among active)
  - `async function updateUserService(id: number, patch): Promise<PublicUser>` — throws `not_found`, `invalid_request` (empty patch or invalid role/session combination), `conflict` (email taken)
  - `async function resetPasswordService(id: number, newPassword: string): Promise<void>` — throws `not_found`; revokes refresh tokens
  - `async function deleteUserService(targetId: number, requesterId: number): Promise<void>` — throws `invalid_request` (self-delete or last-admin-delete), `not_found`; revokes refresh tokens
  - `async function reactivateUserService(id: number): Promise<void>` — throws `not_found`

- [ ] **Step 1: Write failing test `tests/services/userService.test.ts`**

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
  findUserByUsername: vi.fn(),
  findUserByUsernameAnyState: vi.fn(),
  findUserById: vi.fn(),
  findUserByIdAnyState: vi.fn(),
  findUserByEmailActive: vi.fn(),
  insertUser: vi.fn(),
  listLearners: vi.fn(),
  listLearnerIds: vi.fn(),
  countLearners: vi.fn(),
  listUsers: vi.fn(),
  updateUserFields: vi.fn(),
  updateUserPassword: vi.fn(),
  softDeleteUser: vi.fn(),
  reactivateUser: vi.fn(),
  countActiveAdmins: vi.fn(),
}));

vi.mock('../../src/db/queries/refreshTokenQueries.js', () => ({
  insertRefreshToken: vi.fn(),
  findRefreshTokenByHash: vi.fn(),
  revokeRefreshToken: vi.fn(),
  revokeAllRefreshTokensForUser: vi.fn(),
  findRefreshTokenByHashForUpdate: vi.fn(),
  insertRefreshTokenTx: vi.fn(),
  revokeRefreshTokenTx: vi.fn(),
}));

const load = async () => {
  const svc = await import('../../src/services/userService.js');
  const uq = await import('../../src/db/queries/userQueries.js');
  const rt = await import('../../src/db/queries/refreshTokenQueries.js');
  return { svc, uq, rt };
};

const learnerRow = {
  id_user: 42,
  username: 'alice',
  password: 'HASH',
  email: 'alice@example.com',
  role: 'learner' as const,
  first_name: 'Alice',
  last_name: 'Doe',
  session: 'AM' as const,
  is_active: true,
  created_at: new Date('2026-01-15T00:00:00Z'),
};

const adminRow = {
  ...learnerRow,
  id_user: 1,
  username: 'admin',
  role: 'admin' as const,
  first_name: null,
  last_name: null,
  email: 'admin@example.com',
};

beforeEach(() => vi.clearAllMocks());

describe('toPublicUser', () => {
  it('strips password and formats created_at as ISO string', async () => {
    const { svc } = await load();
    const pub = svc.toPublicUser(learnerRow);
    expect(pub).toEqual({
      id: 42,
      username: 'alice',
      email: 'alice@example.com',
      role: 'learner',
      session: 'AM',
      first_name: 'Alice',
      last_name: 'Doe',
      is_active: true,
      created_at: '2026-01-15T00:00:00.000Z',
    });
    expect((pub as any).password).toBeUndefined();
  });
});

describe('listUsersService', () => {
  it('returns paged list with total', async () => {
    const { svc, uq } = await load();
    (uq.listUsers as any).mockResolvedValue({ list: [learnerRow, adminRow], total: 2 });
    const r = await svc.listUsersService({}, 1, 20);
    expect(r.total).toBe(2);
    expect(r.list).toHaveLength(2);
    expect(r.list[0].id).toBe(42);
    expect(r.page).toBe(1);
    expect(r.per_page).toBe(20);
  });
});

describe('getUserService', () => {
  it('returns public user for existing id', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue(learnerRow);
    const pub = await svc.getUserService(42);
    expect(pub.id).toBe(42);
  });

  it('throws not_found when missing', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue(null);
    await expect(svc.getUserService(999)).rejects.toMatchObject({ code: 'not_found' });
  });
});

describe('createUserService', () => {
  it('creates a learner and returns public user', async () => {
    const { svc, uq } = await load();
    (uq.findUserByUsernameAnyState as any).mockResolvedValue(null);
    (uq.findUserByEmailActive as any).mockResolvedValue(null);
    (uq.insertUser as any).mockResolvedValue(42);
    (uq.findUserByIdAnyState as any).mockResolvedValue(learnerRow);

    const pub = await svc.createUserService({
      username: 'alice',
      password: 'hunter2',
      email: 'alice@example.com',
      role: 'learner',
      session: 'AM',
      first_name: 'Alice',
      last_name: 'Doe',
    });
    expect(pub.id).toBe(42);
    expect(uq.insertUser).toHaveBeenCalledOnce();
  });

  it('rejects when session missing for learner', async () => {
    const { svc } = await load();
    await expect(
      svc.createUserService({
        username: 'x',
        password: 'p',
        email: 'x@x',
        role: 'learner',
      } as any),
    ).rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('accepts admin without session', async () => {
    const { svc, uq } = await load();
    (uq.findUserByUsernameAnyState as any).mockResolvedValue(null);
    (uq.findUserByEmailActive as any).mockResolvedValue(null);
    (uq.insertUser as any).mockResolvedValue(1);
    (uq.findUserByIdAnyState as any).mockResolvedValue(adminRow);

    const pub = await svc.createUserService({
      username: 'admin',
      password: 'hunter2',
      email: 'admin@example.com',
      role: 'admin',
    });
    expect(pub.role).toBe('admin');
  });

  it('throws conflict on duplicate username', async () => {
    const { svc, uq } = await load();
    (uq.findUserByUsernameAnyState as any).mockResolvedValue(learnerRow);
    await expect(
      svc.createUserService({
        username: 'alice',
        password: 'p',
        email: 'other@example.com',
        role: 'learner',
        session: 'AM',
      }),
    ).rejects.toMatchObject({ code: 'conflict' });
  });

  it('throws conflict on duplicate active email', async () => {
    const { svc, uq } = await load();
    (uq.findUserByUsernameAnyState as any).mockResolvedValue(null);
    (uq.findUserByEmailActive as any).mockResolvedValue(learnerRow);
    await expect(
      svc.createUserService({
        username: 'newuser',
        password: 'p',
        email: 'alice@example.com',
        role: 'learner',
        session: 'AM',
      }),
    ).rejects.toMatchObject({ code: 'conflict' });
  });
});

describe('updateUserService', () => {
  it('updates first_name and returns fresh public user', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any)
      .mockResolvedValueOnce(learnerRow)
      .mockResolvedValueOnce({ ...learnerRow, first_name: 'Alicia' });
    const pub = await svc.updateUserService(42, { first_name: 'Alicia' });
    expect(pub.first_name).toBe('Alicia');
    expect(uq.updateUserFields).toHaveBeenCalledWith(42, { first_name: 'Alicia' });
  });

  it('throws not_found when user missing', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue(null);
    await expect(svc.updateUserService(999, { first_name: 'X' })).rejects.toMatchObject({ code: 'not_found' });
  });

  it('throws conflict when new email taken by another active user', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue(learnerRow);
    (uq.findUserByEmailActive as any).mockResolvedValue({ ...learnerRow, id_user: 99 });
    await expect(svc.updateUserService(42, { email: 'taken@example.com' })).rejects.toMatchObject({ code: 'conflict' });
  });

  it('allows updating email to the same user own address (idempotent)', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any)
      .mockResolvedValueOnce(learnerRow)
      .mockResolvedValueOnce(learnerRow);
    (uq.findUserByEmailActive as any).mockResolvedValue(learnerRow);
    const pub = await svc.updateUserService(42, { email: 'alice@example.com' });
    expect(pub.email).toBe('alice@example.com');
  });

  it('rejects role=learner update without session when learner has no existing session', async () => {
    const { svc, uq } = await load();
    // hypothetical existing admin being demoted with no session in patch
    (uq.findUserByIdAnyState as any).mockResolvedValue(adminRow);
    // admin's existing session field is 'AM' (DB default), so it IS present; test the intended guard
    // Only reject when both are missing. Here we simulate by patching to a hypothetical no-session row.
    const noSession = { ...adminRow, session: undefined as any };
    (uq.findUserByIdAnyState as any).mockResolvedValueOnce(noSession);
    await expect(svc.updateUserService(1, { role: 'learner' })).rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('throws invalid_request on empty patch', async () => {
    const { svc } = await load();
    await expect(svc.updateUserService(42, {})).rejects.toMatchObject({ code: 'invalid_request' });
  });
});

describe('resetPasswordService', () => {
  it('hashes, updates, and revokes refresh tokens', async () => {
    const { svc, uq, rt } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue(learnerRow);
    await svc.resetPasswordService(42, 'newpassword');
    expect(uq.updateUserPassword).toHaveBeenCalledWith(42, expect.any(String));
    expect(rt.revokeAllRefreshTokensForUser).toHaveBeenCalledWith(42);
  });

  it('throws not_found when user missing', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue(null);
    await expect(svc.resetPasswordService(999, 'p')).rejects.toMatchObject({ code: 'not_found' });
  });
});

describe('deleteUserService', () => {
  it('soft-deletes target and revokes refresh tokens', async () => {
    const { svc, uq, rt } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue(learnerRow);
    await svc.deleteUserService(42, 1);
    expect(uq.softDeleteUser).toHaveBeenCalledWith(42);
    expect(rt.revokeAllRefreshTokensForUser).toHaveBeenCalledWith(42);
  });

  it('rejects self-delete', async () => {
    const { svc } = await load();
    await expect(svc.deleteUserService(1, 1)).rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('rejects last-admin delete', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue(adminRow);
    (uq.countActiveAdmins as any).mockResolvedValue(1);
    await expect(svc.deleteUserService(1, 99)).rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('allows deleting an admin when others exist', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue(adminRow);
    (uq.countActiveAdmins as any).mockResolvedValue(2);
    await svc.deleteUserService(1, 99);
    expect(uq.softDeleteUser).toHaveBeenCalledWith(1);
  });

  it('throws not_found when target missing', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue(null);
    await expect(svc.deleteUserService(999, 1)).rejects.toMatchObject({ code: 'not_found' });
  });
});

describe('reactivateUserService', () => {
  it('reactivates existing user', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue({ ...learnerRow, is_active: false });
    await svc.reactivateUserService(42);
    expect(uq.reactivateUser).toHaveBeenCalledWith(42);
  });

  it('throws not_found when user missing', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue(null);
    await expect(svc.reactivateUserService(999)).rejects.toMatchObject({ code: 'not_found' });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/services/userService.test.ts`
Expected: FAIL — module `userService.js` not found.

- [ ] **Step 3: Create `src/services/userService.ts`**

```ts
import { AppError } from '../lib/errors.js';
import { hashPassword } from './passwordService.js';
import { revokeAllRefreshTokensForUser } from '../db/queries/refreshTokenQueries.js';
import {
  UserRow,
  findUserByIdAnyState,
  findUserByUsernameAnyState,
  findUserByEmailActive,
  insertUser,
  listUsers,
  updateUserFields,
  updateUserPassword,
  softDeleteUser,
  reactivateUser,
  countActiveAdmins,
} from '../db/queries/userQueries.js';

export interface PublicUser {
  id: number;
  username: string;
  email: string;
  role: 'admin' | 'learner';
  session: 'AM' | 'PM';
  first_name: string | null;
  last_name: string | null;
  is_active: boolean;
  created_at: string;
}

export function toPublicUser(row: UserRow): PublicUser {
  return {
    id: row.id_user,
    username: row.username,
    email: row.email,
    role: row.role,
    session: row.session,
    first_name: row.first_name,
    last_name: row.last_name,
    is_active: row.is_active,
    created_at: row.created_at.toISOString(),
  };
}

export async function listUsersService(
  filter: { role?: 'admin' | 'learner'; session?: 'AM' | 'PM'; name?: string; includeInactive?: boolean },
  page: number,
  perPage: number,
): Promise<{ list: PublicUser[]; total: number; page: number; per_page: number }> {
  const { list, total } = await listUsers(filter, page, perPage);
  return {
    list: list.map(toPublicUser),
    total,
    page,
    per_page: perPage,
  };
}

export async function getUserService(id: number): Promise<PublicUser> {
  const row = await findUserByIdAnyState(id);
  if (!row) throw new AppError('not_found', 'User not found');
  return toPublicUser(row);
}

export async function createUserService(input: {
  username: string;
  password: string;
  email: string;
  role: 'admin' | 'learner';
  session?: 'AM' | 'PM';
  first_name?: string | null;
  last_name?: string | null;
}): Promise<PublicUser> {
  if (input.role === 'learner' && input.session === undefined) {
    throw new AppError('invalid_request', 'session is required when role is learner');
  }

  const existingByUsername = await findUserByUsernameAnyState(input.username);
  if (existingByUsername) {
    throw new AppError('conflict', 'Username already exists');
  }
  const existingByEmail = await findUserByEmailActive(input.email);
  if (existingByEmail) {
    throw new AppError('conflict', 'Email already exists');
  }

  const passwordHash = await hashPassword(input.password);
  const id = await insertUser({
    username: input.username,
    passwordHash,
    email: input.email,
    role: input.role,
    firstName: input.first_name ?? undefined,
    lastName: input.last_name ?? undefined,
    session: input.role === 'learner' ? input.session : undefined,
  });
  const row = await findUserByIdAnyState(id);
  if (!row) throw new AppError('internal_error', 'User created but could not be read back');
  return toPublicUser(row);
}

export async function updateUserService(
  id: number,
  patch: {
    email?: string;
    role?: 'admin' | 'learner';
    session?: 'AM' | 'PM';
    first_name?: string | null;
    last_name?: string | null;
  },
): Promise<PublicUser> {
  if (Object.keys(patch).length === 0) {
    throw new AppError('invalid_request', 'Empty patch');
  }

  const existing = await findUserByIdAnyState(id);
  if (!existing) throw new AppError('not_found', 'User not found');

  // Uniqueness: if email is changing, ensure it is not held by another active user.
  if (patch.email !== undefined && patch.email !== existing.email) {
    const collide = await findUserByEmailActive(patch.email);
    if (collide && collide.id_user !== id) {
      throw new AppError('conflict', 'Email already exists');
    }
  }

  // If final role would be 'learner', ensure a session is defined (either in patch or already present).
  const finalRole = patch.role ?? existing.role;
  if (finalRole === 'learner') {
    const finalSession = patch.session ?? existing.session;
    if (finalSession === undefined) {
      throw new AppError('invalid_request', 'session is required when role is learner');
    }
  }

  await updateUserFields(id, patch);
  const fresh = await findUserByIdAnyState(id);
  if (!fresh) throw new AppError('internal_error', 'User updated but could not be read back');
  return toPublicUser(fresh);
}

export async function resetPasswordService(id: number, newPassword: string): Promise<void> {
  const existing = await findUserByIdAnyState(id);
  if (!existing) throw new AppError('not_found', 'User not found');
  const hash = await hashPassword(newPassword);
  await updateUserPassword(id, hash);
  await revokeAllRefreshTokensForUser(id);
}

export async function deleteUserService(targetId: number, requesterId: number): Promise<void> {
  if (targetId === requesterId) {
    throw new AppError('invalid_request', 'Cannot delete yourself');
  }
  const target = await findUserByIdAnyState(targetId);
  if (!target) throw new AppError('not_found', 'User not found');
  if (target.role === 'admin' && target.is_active) {
    const activeAdmins = await countActiveAdmins();
    if (activeAdmins <= 1) {
      throw new AppError('invalid_request', 'Cannot delete the last active admin');
    }
  }
  await softDeleteUser(targetId);
  await revokeAllRefreshTokensForUser(targetId);
}

export async function reactivateUserService(id: number): Promise<void> {
  const existing = await findUserByIdAnyState(id);
  if (!existing) throw new AppError('not_found', 'User not found');
  await reactivateUser(id);
}
```

- [ ] **Step 4: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/services/userService.test.ts`
Expected: PASS. Should be about 17 tests total from the file.

If any test fails, the most common cause is a mock returning a different shape than the service expects — fix the mock's return value to match.

- [ ] **Step 5: Type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add Aegis-Backend/src/services/userService.ts Aegis-Backend/tests/services/userService.test.ts
git commit -m "feat(users): add userService with CRUD, safeguards, and token revocation"
```

---

## Task 5: `admin/users` router

**Files:**
- Create: `Aegis-Backend/src/routes/admin/users.ts`
- Create: `Aegis-Backend/tests/routes/adminUsers.test.ts`

**Interfaces:**
- Consumes: `requireAuth`, `requireRole('admin')`, `AppError`, all functions from `userService`
- Produces: `usersRouter` — exports one Express Router with all 7 endpoints under `/admin/users`

- [ ] **Step 1: Write failing test `tests/routes/adminUsers.test.ts`**

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

vi.mock('../../src/services/userService.js', () => ({
  listUsersService: vi.fn(),
  getUserService: vi.fn(),
  createUserService: vi.fn(),
  updateUserService: vi.fn(),
  resetPasswordService: vi.fn(),
  deleteUserService: vi.fn(),
  reactivateUserService: vi.fn(),
  toPublicUser: vi.fn(),
}));

const buildTestApp = async (role: 'admin' | 'learner' = 'admin', sub = 1) => {
  const { errorHandler } = await import('../../src/middleware/errorHandler.js');
  const { usersRouter } = await import('../../src/routes/admin/users.js');
  const { signAccessToken } = await import('../../src/services/tokenService.js');
  const app = express();
  app.use(express.json());
  app.use('/api/v1/admin/users', usersRouter);
  app.use(errorHandler);
  const token = signAccessToken({ sub, role });
  return { app, token };
};

beforeEach(() => vi.clearAllMocks());

describe('GET /api/v1/admin/users', () => {
  it('returns paged list', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/userService.js');
    (svc.listUsersService as any).mockResolvedValue({
      list: [], total: 0, page: 1, per_page: 20,
    });
    const res = await request(app)
      .get('/api/v1/admin/users?page=1&per_page=20')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.total).toBe(0);
  });

  it('rejects learner tokens with 403', async () => {
    const { app, token } = await buildTestApp('learner');
    const res = await request(app)
      .get('/api/v1/admin/users')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(403);
  });

  it('rejects invalid session filter with 400', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .get('/api/v1/admin/users?session=XX')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });
});

describe('GET /api/v1/admin/users/:id', () => {
  it('returns 200 on success', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/userService.js');
    (svc.getUserService as any).mockResolvedValue({ id: 42, username: 'a' });
    const res = await request(app)
      .get('/api/v1/admin/users/42')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.id).toBe(42);
  });

  it('returns 404 when user missing', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/userService.js');
    const { AppError } = await import('../../src/lib/errors.js');
    (svc.getUserService as any).mockRejectedValue(new AppError('not_found'));
    const res = await request(app)
      .get('/api/v1/admin/users/999')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });

  it('rejects non-numeric id with 400', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .get('/api/v1/admin/users/abc')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });
});

describe('POST /api/v1/admin/users', () => {
  it('returns 201 with the created user', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/userService.js');
    (svc.createUserService as any).mockResolvedValue({ id: 42, username: 'alice' });
    const res = await request(app)
      .post('/api/v1/admin/users')
      .set('Authorization', `Bearer ${token}`)
      .send({
        username: 'alice',
        password: 'hunter2',
        email: 'alice@example.com',
        role: 'learner',
        session: 'AM',
      });
    expect(res.status).toBe(201);
    expect(res.body.id).toBe(42);
  });

  it('returns 409 on conflict from service', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/userService.js');
    const { AppError } = await import('../../src/lib/errors.js');
    (svc.createUserService as any).mockRejectedValue(new AppError('conflict'));
    const res = await request(app)
      .post('/api/v1/admin/users')
      .set('Authorization', `Bearer ${token}`)
      .send({
        username: 'alice',
        password: 'hunter2',
        email: 'alice@example.com',
        role: 'learner',
        session: 'AM',
      });
    expect(res.status).toBe(409);
  });

  it('rejects body with unknown key (strict)', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .post('/api/v1/admin/users')
      .set('Authorization', `Bearer ${token}`)
      .send({
        username: 'alice',
        password: 'hunter2',
        email: 'alice@example.com',
        role: 'learner',
        session: 'AM',
        extra: 'bad',
      });
    expect(res.status).toBe(400);
  });

  it('rejects password > 72 chars', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .post('/api/v1/admin/users')
      .set('Authorization', `Bearer ${token}`)
      .send({
        username: 'alice',
        password: 'x'.repeat(73),
        email: 'alice@example.com',
        role: 'learner',
        session: 'AM',
      });
    expect(res.status).toBe(400);
  });
});

describe('PATCH /api/v1/admin/users/:id', () => {
  it('returns 200 with updated user', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/userService.js');
    (svc.updateUserService as any).mockResolvedValue({ id: 42, first_name: 'Alicia' });
    const res = await request(app)
      .patch('/api/v1/admin/users/42')
      .set('Authorization', `Bearer ${token}`)
      .send({ first_name: 'Alicia' });
    expect(res.status).toBe(200);
    expect(res.body.first_name).toBe('Alicia');
  });

  it('rejects password field in patch (must use dedicated endpoint)', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .patch('/api/v1/admin/users/42')
      .set('Authorization', `Bearer ${token}`)
      .send({ password: 'bad' });
    expect(res.status).toBe(400);
  });

  it('rejects username field in patch', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .patch('/api/v1/admin/users/42')
      .set('Authorization', `Bearer ${token}`)
      .send({ username: 'new-name' });
    expect(res.status).toBe(400);
  });

  it('rejects is_active field in patch', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .patch('/api/v1/admin/users/42')
      .set('Authorization', `Bearer ${token}`)
      .send({ is_active: false });
    expect(res.status).toBe(400);
  });
});

describe('PUT /api/v1/admin/users/:id/password', () => {
  it('returns 204 on success', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/userService.js');
    (svc.resetPasswordService as any).mockResolvedValue(undefined);
    const res = await request(app)
      .put('/api/v1/admin/users/42/password')
      .set('Authorization', `Bearer ${token}`)
      .send({ new_password: 'changeme' });
    expect(res.status).toBe(204);
    expect(svc.resetPasswordService).toHaveBeenCalledWith(42, 'changeme');
  });

  it('rejects missing new_password with 400', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .put('/api/v1/admin/users/42/password')
      .set('Authorization', `Bearer ${token}`)
      .send({});
    expect(res.status).toBe(400);
  });
});

describe('DELETE /api/v1/admin/users/:id', () => {
  it('returns 204 on success and passes requester id from JWT', async () => {
    const { app, token } = await buildTestApp('admin', 1);
    const svc = await import('../../src/services/userService.js');
    (svc.deleteUserService as any).mockResolvedValue(undefined);
    const res = await request(app)
      .delete('/api/v1/admin/users/42')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(204);
    expect(svc.deleteUserService).toHaveBeenCalledWith(42, 1);
  });

  it('returns 400 on self-delete (from service)', async () => {
    const { app, token } = await buildTestApp('admin', 1);
    const svc = await import('../../src/services/userService.js');
    const { AppError } = await import('../../src/lib/errors.js');
    (svc.deleteUserService as any).mockRejectedValue(new AppError('invalid_request'));
    const res = await request(app)
      .delete('/api/v1/admin/users/1')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });
});

describe('POST /api/v1/admin/users/:id/reactivate', () => {
  it('returns 204 on success', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/userService.js');
    (svc.reactivateUserService as any).mockResolvedValue(undefined);
    const res = await request(app)
      .post('/api/v1/admin/users/42/reactivate')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(204);
    expect(svc.reactivateUserService).toHaveBeenCalledWith(42);
  });

  it('returns 404 when user missing', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/userService.js');
    const { AppError } = await import('../../src/lib/errors.js');
    (svc.reactivateUserService as any).mockRejectedValue(new AppError('not_found'));
    const res = await request(app)
      .post('/api/v1/admin/users/999/reactivate')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/routes/adminUsers.test.ts`
Expected: FAIL — router module not found.

- [ ] **Step 3: Create `src/routes/admin/users.ts`**

```ts
import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../middleware/requireAuth.js';
import { requireRole } from '../../middleware/requireRole.js';
import { AppError } from '../../lib/errors.js';
import {
  listUsersService,
  getUserService,
  createUserService,
  updateUserService,
  resetPasswordService,
  deleteUserService,
  reactivateUserService,
} from '../../services/userService.js';

const idParam = z.object({ id: z.coerce.number().int().positive() });

const listQuerySchema = z.object({
  role: z.enum(['admin', 'learner']).optional(),
  session: z.enum(['AM', 'PM']).optional(),
  name: z.string().max(100).optional(),
  include_inactive: z.coerce.boolean().optional(),
  page: z.coerce.number().int().min(1).default(1),
  per_page: z.coerce.number().int().min(1).max(100).default(20),
});

const createBodySchema = z.object({
  username: z.string().min(1).max(50),
  password: z.string().min(1).max(72),
  email: z.string().email().max(100),
  role: z.enum(['admin', 'learner']),
  session: z.enum(['AM', 'PM']).optional(),
  first_name: z.string().max(50).nullable().optional(),
  last_name: z.string().max(50).nullable().optional(),
}).strict();

const patchBodySchema = z.object({
  email: z.string().email().max(100).optional(),
  role: z.enum(['admin', 'learner']).optional(),
  session: z.enum(['AM', 'PM']).optional(),
  first_name: z.string().max(50).nullable().optional(),
  last_name: z.string().max(50).nullable().optional(),
}).strict();

const passwordBodySchema = z.object({
  new_password: z.string().min(1).max(72),
}).strict();

export const usersRouter = Router();

usersRouter.get('/', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = listQuerySchema.safeParse(req.query);
  if (!parsed.success) return next(new AppError('invalid_request'));
  const { role, session, name, include_inactive, page, per_page } = parsed.data;
  try {
    const result = await listUsersService(
      { role, session, name, includeInactive: include_inactive },
      page,
      per_page,
    );
    res.json(result);
  } catch (err) {
    next(err);
  }
});

usersRouter.get('/:id', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = idParam.safeParse(req.params);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    const user = await getUserService(parsed.data.id);
    res.json(user);
  } catch (err) {
    next(err);
  }
});

usersRouter.post('/', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = createBodySchema.safeParse(req.body);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    const user = await createUserService(parsed.data);
    res.status(201).json(user);
  } catch (err) {
    next(err);
  }
});

usersRouter.patch('/:id', requireAuth, requireRole('admin'), async (req, res, next) => {
  const idParsed = idParam.safeParse(req.params);
  if (!idParsed.success) return next(new AppError('invalid_request'));
  const bodyParsed = patchBodySchema.safeParse(req.body);
  if (!bodyParsed.success) return next(new AppError('invalid_request'));
  try {
    const user = await updateUserService(idParsed.data.id, bodyParsed.data);
    res.json(user);
  } catch (err) {
    next(err);
  }
});

usersRouter.put('/:id/password', requireAuth, requireRole('admin'), async (req, res, next) => {
  const idParsed = idParam.safeParse(req.params);
  if (!idParsed.success) return next(new AppError('invalid_request'));
  const bodyParsed = passwordBodySchema.safeParse(req.body);
  if (!bodyParsed.success) return next(new AppError('invalid_request'));
  try {
    await resetPasswordService(idParsed.data.id, bodyParsed.data.new_password);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});

usersRouter.delete('/:id', requireAuth, requireRole('admin'), async (req, res, next) => {
  const idParsed = idParam.safeParse(req.params);
  if (!idParsed.success) return next(new AppError('invalid_request'));
  try {
    await deleteUserService(idParsed.data.id, req.user!.id);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});

usersRouter.post('/:id/reactivate', requireAuth, requireRole('admin'), async (req, res, next) => {
  const idParsed = idParam.safeParse(req.params);
  if (!idParsed.success) return next(new AppError('invalid_request'));
  try {
    await reactivateUserService(idParsed.data.id);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});
```

- [ ] **Step 4: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/routes/adminUsers.test.ts`
Expected: PASS. About 17 route tests.

- [ ] **Step 5: Type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add Aegis-Backend/src/routes/admin/users.ts Aegis-Backend/tests/routes/adminUsers.test.ts
git commit -m "feat(admin): add /admin/users router with 7 CRUD endpoints"
```

---

## Task 6: Mount `usersRouter` in `app.ts`

**Files:**
- Modify: `Aegis-Backend/src/app.ts`

**Interfaces:**
- Consumes: `usersRouter` from Task 5
- Produces: `/api/v1/admin/users/*` becomes a live route mount

- [ ] **Step 1: Update `src/app.ts`**

Add the import and mount. Change the import block at the top to include `usersRouter`:

```ts
import { rollupRouter } from './routes/admin/rollup.js';
import { usersRouter } from './routes/admin/users.js';
import { errorHandler } from './middleware/errorHandler.js';
```

And add the mount, in the admin group after `rollupRouter`:

```ts
  app.use('/api/v1/admin/rollup', rollupRouter);
  app.use('/api/v1/admin/users', usersRouter);
```

The full `buildApp()` should now look like:

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
import { usersRouter } from './routes/admin/users.js';
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
  app.use('/api/v1/admin/users', usersRouter);

  app.use(errorHandler);
  return app;
}
```

- [ ] **Step 2: Type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 3: Run full test suite**

Run: `cd Aegis-Backend && npm test`
Expected: all tests pass (baseline + userService tests + admin user route tests). Approximate count: 102 (baseline on main) + ~17 (userService) + ~17 (adminUsers routes) ≈ 136 total.

- [ ] **Step 4: Lint**

Run: `cd Aegis-Backend && npm run lint`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add Aegis-Backend/src/app.ts
git commit -m "feat(app): mount /admin/users router"
```

---

## Task 7: Final integration checks

**Files:** none new; verification only.

- [ ] **Step 1: Full type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 2: Full test suite**

Run: `cd Aegis-Backend && npm test`
Expected: every test passes. Reasonable overall total ~136.

- [ ] **Step 3: Lint**

Run: `cd Aegis-Backend && npm run lint`
Expected: exit 0.

- [ ] **Step 4: Verify migration file sorts correctly**

Run: `ls Aegis-Backend/migrations/`
Expected output includes `0006_user_is_active.sql` after `0005_system_config.sql`.

---

## Verification checklist (post-implementation)

- All new tests pass; full suite passes; tsc clean; lint clean.
- `npm run migrate` on an empty MySQL applies migrations 0001–0006 without error; `USER` has `is_active` column.
- Existing admin login flow still works (seeded admin can log in).
- `POST /api/v1/admin/users` with a new learner returns 201 with the created user.
- `PATCH /api/v1/admin/users/:id` cannot change `username`, `password`, or `is_active` (400).
- `DELETE /api/v1/admin/users/:id` on self returns 400.
- `DELETE /api/v1/admin/users/:id` on the only remaining admin returns 400.
- `POST /api/v1/admin/users/:id/reactivate` flips `is_active` back to TRUE; a user reactivated can log in again.
- After `DELETE`, that user's refresh tokens are revoked (subsequent `/auth/refresh` returns 401 `invalid_grant`).
