# Aegis Rooms + Beacons CRUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 8 admin CRUD endpoints for `ROOM` and `DEVICE` — 3 new for rooms (create/update/delete) alongside the existing list route, and 4 new for beacons (list/create/update/delete).

**Architecture:** Reuse the established layering (routes → services → queries). Extend existing `roomsService.ts` with write functions. Add a new `beaconsService.ts` for device CRUD. Extend query modules. New admin beacons router; existing admin rooms router grows to hold the new methods.

**Tech Stack:** Same as prior features — Node.js 20+, TypeScript strict, Express 4, mysql2/promise, zod, pino, Vitest, supertest.

## Global Constraints

- TypeScript strict; ES modules; `.js` extension on TS imports.
- DB access only in `src/db/*`.
- Every admin route chains `requireAuth` + `requireRole('admin')`.
- Zod `.strict()` on write bodies (POST/PATCH) → unknown keys rejected.
- Errors always via `next(err)`; error handler translates.
- Response bodies use `snake_case`.
- HTTP: 200 for GET/PATCH, 201 for POST create, 204 for DELETE.
- Room delete blocked if `SELECT COUNT(*) FROM PRESENCE_LOG WHERE id_room = ?` > 0 → return `AppError('conflict')` (409).
- Beacon delete has NO guard (hardware disappears freely; no dependent FKs).
- Room name: 1–100 chars, no uniqueness constraint.
- Device `identifier`: 1–100 chars, unique across all devices (409 on collision).
- Device `id_room`: nullable — spare beacons allowed.
- Response shapes:
  - `Room`: `{ id: number; name: string }` — matches existing `RoomResource`.
  - `Device (admin)`: `{ id: number; name: string; beacon_identifier: string; room_id: number | null; room_name: string | null }`.
  - Learner-facing `GET /api/v1/beacons` shape is UNCHANGED (`{ beacon_identifier, room_id, room_name }`).

---

## File Structure

**Created:**
- `Aegis-Backend/src/services/beaconsService.ts` — CRUD orchestration for devices (uniqueness + room-existence checks).
- `Aegis-Backend/src/routes/admin/beacons.ts` — admin router mounting 4 device endpoints under `/api/v1/admin/beacons`.
- `Aegis-Backend/tests/services/beaconsService.test.ts`
- `Aegis-Backend/tests/routes/adminBeacons.test.ts`

**Modified:**
- `Aegis-Backend/src/db/queries/roomQueries.ts` — add `insertRoom`, `updateRoomName`, `deleteRoom`.
- `Aegis-Backend/src/db/queries/deviceQueries.ts` — extend `DeviceWithRoom` interface (`id_room` and `room_name` become nullable to represent unassigned devices), add `listDevices`, `findDeviceById`, `findDeviceByIdentifier`, `insertDevice`, `updateDevice`, `deleteDevice`.
- `Aegis-Backend/src/db/queries/presenceQueries.ts` — add `countPresenceLogsForRoom(roomId): Promise<number>` for the delete guard.
- `Aegis-Backend/src/services/roomsService.ts` — add `createRoomService`, `updateRoomService`, `deleteRoomService` (with presence-log guard) and their public response types.
- `Aegis-Backend/src/routes/admin/rooms.ts` — add POST `/`, PATCH `/:room_id`, DELETE `/:room_id` handlers.
- `Aegis-Backend/src/app.ts` — mount `beaconsRouter` at `/api/v1/admin/beacons`.
- `Aegis-Backend/tests/services/roomsService.test.ts` — extend with CRUD test coverage.
- `Aegis-Backend/tests/routes/adminRooms.test.ts` — extend with CRUD test coverage.

**Not affected:**
- Learner-facing `GET /api/v1/beacons` route and its underlying `listAssignedDevices` remain unchanged in behavior. `listAssignedDevices` continues to return only assigned devices with `id_room NOT NULL`; the new admin route uses new query functions.
- Live-radar routes (`/admin/rooms/:id/map`, `/current-occupants`, `/additional-data`) unchanged.

---

## Task 1: Extend `roomQueries` and `presenceQueries` with the write + guard queries

**Files:**
- Modify: `Aegis-Backend/src/db/queries/roomQueries.ts`
- Modify: `Aegis-Backend/src/db/queries/presenceQueries.ts`

**Interfaces:**
- Consumes: `pool` from `src/db/pool.ts`.
- Produces (roomQueries):
  - `async function insertRoom(name: string): Promise<number>` — returns new id
  - `async function updateRoomName(id: number, name: string): Promise<void>`
  - `async function deleteRoom(id: number): Promise<void>`
- Produces (presenceQueries):
  - `async function countPresenceLogsForRoom(roomId: number): Promise<number>`

Existing exports (`listRooms`, `findRoomById`) are unchanged.

- [ ] **Step 1: Append writes to `src/db/queries/roomQueries.ts`**

Change the imports at the top (line 1) to also pull `ResultSetHeader`:

```ts
import { RowDataPacket, ResultSetHeader } from 'mysql2';
```

Then append these three functions at the end of the file:

```ts
export async function insertRoom(name: string): Promise<number> {
  const [result] = await pool.query<ResultSetHeader>(
    'INSERT INTO `ROOM` (`name`) VALUES (?)',
    [name],
  );
  return result.insertId;
}

export async function updateRoomName(id: number, name: string): Promise<void> {
  await pool.query(
    'UPDATE `ROOM` SET `name` = ? WHERE `id_room` = ?',
    [name, id],
  );
}

export async function deleteRoom(id: number): Promise<void> {
  await pool.query('DELETE FROM `ROOM` WHERE `id_room` = ?', [id]);
}
```

- [ ] **Step 2: Append the presence-log count helper to `src/db/queries/presenceQueries.ts`**

Append at the end of the file:

```ts
export async function countPresenceLogsForRoom(roomId: number): Promise<number> {
  const [rows] = await pool.query<({ c: number } & RowDataPacket)[]>(
    'SELECT COUNT(*) AS c FROM `PRESENCE_LOG` WHERE `id_room` = ?',
    [roomId],
  );
  return rows[0]?.c ?? 0;
}
```

- [ ] **Step 3: Type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 4: Full test suite (no regression)**

Run: `cd Aegis-Backend && npm test`
Expected: all existing tests still pass. The baseline on latest main includes the merged user-crud suite. Confirm none of them regressed.

- [ ] **Step 5: Commit**

```bash
cd /Users/workspace/Documents/personal/fiveie/aegis/.claude/worktrees/jazzy-humming-sphinx
git add Aegis-Backend/src/db/queries/roomQueries.ts Aegis-Backend/src/db/queries/presenceQueries.ts
git commit -m "feat(db): add room CRUD queries and presence-log count helper"
```

---

## Task 2: Extend `deviceQueries` with full CRUD

**Files:**
- Modify: `Aegis-Backend/src/db/queries/deviceQueries.ts`

**Interfaces:**
- Consumes: `pool` from `src/db/pool.ts`.
- Produces:
  - Modified interface: `DeviceWithRoom { id_device: number; name: string; identifier: string; id_room: number | null; room_name: string | null }` — adds `name` field, makes `id_room` and `room_name` nullable
  - `listAssignedDevices()` — unchanged behavior (still only assigned) but return type updated to reflect nullable columns (in practice `id_room` and `room_name` will never be null for assigned rows, but TS type must match table shape)
  - `async function listDevices(filter: { assigned?: boolean; roomId?: number }, page: number, perPage: number): Promise<{ list: DeviceWithRoom[]; total: number }>`
  - `async function findDeviceById(id: number): Promise<DeviceWithRoom | null>`
  - `async function findDeviceByIdentifier(identifier: string): Promise<DeviceWithRoom | null>`
  - `async function insertDevice(input: { name: string; identifier: string; id_room: number | null }): Promise<number>`
  - `async function updateDevice(id: number, patch: { name?: string; identifier?: string; id_room?: number | null }): Promise<void>`
  - `async function deleteDevice(id: number): Promise<void>`

- [ ] **Step 1: Replace the file with the extended version**

Overwrite `Aegis-Backend/src/db/queries/deviceQueries.ts` with the following complete content:

```ts
import { RowDataPacket, ResultSetHeader } from 'mysql2';
import { pool } from '../pool.js';

export interface DeviceWithRoom {
  id_device: number;
  name: string;
  identifier: string;
  id_room: number | null;
  room_name: string | null;
}

const SELECT_DEVICE = `
  SELECT d.\`id_device\`, d.\`name\`, d.\`identifier\`, d.\`id_room\`, r.\`name\` AS room_name
  FROM \`DEVICE\` d
  LEFT JOIN \`ROOM\` r ON r.\`id_room\` = d.\`id_room\`
`;

export async function listAssignedDevices(): Promise<DeviceWithRoom[]> {
  const [rows] = await pool.query<(DeviceWithRoom & RowDataPacket)[]>(
    `${SELECT_DEVICE}
     WHERE d.\`id_room\` IS NOT NULL
     ORDER BY d.\`id_device\` ASC`,
  );
  return rows;
}

export async function listDevices(
  filter: { assigned?: boolean; roomId?: number },
  page: number,
  perPage: number,
): Promise<{ list: DeviceWithRoom[]; total: number }> {
  const conds: string[] = [];
  const params: unknown[] = [];
  if (filter.assigned === true) conds.push('d.`id_room` IS NOT NULL');
  else if (filter.assigned === false) conds.push('d.`id_room` IS NULL');
  if (filter.roomId !== undefined) {
    conds.push('d.`id_room` = ?');
    params.push(filter.roomId);
  }
  const where = conds.length > 0 ? 'WHERE ' + conds.join(' AND ') : '';

  const [countRows] = await pool.query<({ c: number } & RowDataPacket)[]>(
    `SELECT COUNT(*) AS c FROM \`DEVICE\` d ${where}`,
    params,
  );
  const total = countRows[0]?.c ?? 0;

  const offset = (page - 1) * perPage;
  const [rows] = await pool.query<(DeviceWithRoom & RowDataPacket)[]>(
    `${SELECT_DEVICE} ${where} ORDER BY d.\`id_device\` ASC LIMIT ? OFFSET ?`,
    [...params, perPage, offset],
  );
  return { list: rows, total };
}

export async function findDeviceById(id: number): Promise<DeviceWithRoom | null> {
  const [rows] = await pool.query<(DeviceWithRoom & RowDataPacket)[]>(
    `${SELECT_DEVICE} WHERE d.\`id_device\` = ? LIMIT 1`,
    [id],
  );
  return rows[0] ?? null;
}

export async function findDeviceByIdentifier(identifier: string): Promise<DeviceWithRoom | null> {
  const [rows] = await pool.query<(DeviceWithRoom & RowDataPacket)[]>(
    `${SELECT_DEVICE} WHERE d.\`identifier\` = ? LIMIT 1`,
    [identifier],
  );
  return rows[0] ?? null;
}

export async function insertDevice(input: {
  name: string;
  identifier: string;
  id_room: number | null;
}): Promise<number> {
  const [result] = await pool.query<ResultSetHeader>(
    'INSERT INTO `DEVICE` (`name`, `identifier`, `id_room`) VALUES (?, ?, ?)',
    [input.name, input.identifier, input.id_room],
  );
  return result.insertId;
}

export async function updateDevice(
  id: number,
  patch: { name?: string; identifier?: string; id_room?: number | null },
): Promise<void> {
  const sets: string[] = [];
  const params: unknown[] = [];
  if (patch.name !== undefined) {
    sets.push('`name` = ?');
    params.push(patch.name);
  }
  if (patch.identifier !== undefined) {
    sets.push('`identifier` = ?');
    params.push(patch.identifier);
  }
  if (patch.id_room !== undefined) {
    sets.push('`id_room` = ?');
    params.push(patch.id_room);
  }
  if (sets.length === 0) return;
  params.push(id);
  await pool.query(
    `UPDATE \`DEVICE\` SET ${sets.join(', ')} WHERE \`id_device\` = ?`,
    params,
  );
}

export async function deleteDevice(id: number): Promise<void> {
  await pool.query('DELETE FROM `DEVICE` WHERE `id_device` = ?', [id]);
}
```

- [ ] **Step 2: Update the learner-facing route to match the new nullable types**

The route `src/routes/beacons.ts` calls `listAssignedDevices()` and maps its output. Because we made `id_room` nullable in the interface, the mapping needs a safety-cast or filter. Confirm by reading the route:

Run: `cat Aegis-Backend/src/routes/beacons.ts`

If the route contains `r.id_room` directly and TypeScript complains about `null` not being assignable to `number` in the response, add a narrowing filter. The existing map is:

```ts
list: rows.map((r) => ({
  beacon_identifier: r.identifier,
  room_id: r.id_room,
  room_name: r.room_name,
})),
```

Since `listAssignedDevices` still WHERE-filters `id_room IS NOT NULL`, the nulls never materialize at runtime, but TypeScript can't know that. Change the response type in that route to explicitly narrow via a filter+assertion, OR — simpler — modify the mapping to non-null-assert:

```ts
list: rows.map((r) => ({
  beacon_identifier: r.identifier,
  room_id: r.id_room as number,       // never null: filtered in the query
  room_name: r.room_name as string,   // never null when id_room is not null
})),
```

- [ ] **Step 3: Type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0. If tsc complains about `id_room` in the beacons route, apply the fix from Step 2.

- [ ] **Step 4: Full test suite (no regression)**

Run: `cd Aegis-Backend && npm test`
Expected: existing tests still pass. If tests around `/api/v1/beacons` (in `learner.test.ts`) fail because the mocked `listAssignedDevices` response is missing the `name` field, add `name: 'iBeacon N'` to those fixtures. Typescript's `as any` cast on route mocks usually absorbs the change; only touch a test if it actually fails.

- [ ] **Step 5: Commit**

```bash
git add Aegis-Backend/src/db/queries/deviceQueries.ts Aegis-Backend/src/routes/beacons.ts
git commit -m "feat(db): extend deviceQueries with CRUD and nullable id_room"
```

---

## Task 3: `roomsService` — add `createRoomService`, `updateRoomService`, `deleteRoomService`

**Files:**
- Modify: `Aegis-Backend/src/services/roomsService.ts`
- Modify: `Aegis-Backend/tests/services/roomsService.test.ts`

**Interfaces:**
- Consumes: `insertRoom`, `updateRoomName`, `deleteRoom`, `findRoomById` from `roomQueries`; `countPresenceLogsForRoom` from `presenceQueries`; `AppError`.
- Produces:
  - `interface RoomResource { id: number; name: string }` (may already exist in the service; if not, add it)
  - `async function createRoomService(input: { name: string }): Promise<RoomResource>`
  - `async function updateRoomService(id: number, patch: { name?: string }): Promise<RoomResource>` — throws `not_found`, `invalid_request` on empty patch
  - `async function deleteRoomService(id: number): Promise<void>` — throws `not_found`, `conflict` if presence logs exist

- [ ] **Step 1: Write failing test cases in `tests/services/roomsService.test.ts`**

Append these new `describe` blocks after the existing tests (before the final closing brace):

```ts
describe('createRoomService', () => {
  it('creates a room and returns the resource', async () => {
    const { svc, rq } = await load();
    (rq.insertRoom as any).mockResolvedValue(42);
    (rq.findRoomById as any).mockResolvedValue({ id_room: 42, name: 'Lab X' });
    const r = await svc.createRoomService({ name: 'Lab X' });
    expect(r).toEqual({ id: 42, name: 'Lab X' });
    expect(rq.insertRoom).toHaveBeenCalledWith('Lab X');
  });
});

describe('updateRoomService', () => {
  it('updates and returns the fresh resource', async () => {
    const { svc, rq } = await load();
    (rq.findRoomById as any).mockResolvedValueOnce({ id_room: 5, name: 'Old' });
    (rq.findRoomById as any).mockResolvedValueOnce({ id_room: 5, name: 'New' });
    const r = await svc.updateRoomService(5, { name: 'New' });
    expect(r).toEqual({ id: 5, name: 'New' });
    expect(rq.updateRoomName).toHaveBeenCalledWith(5, 'New');
  });

  it('throws not_found when room missing', async () => {
    const { svc, rq } = await load();
    (rq.findRoomById as any).mockResolvedValue(null);
    await expect(svc.updateRoomService(999, { name: 'X' })).rejects.toMatchObject({ code: 'not_found' });
  });

  it('throws invalid_request on empty patch', async () => {
    const { svc } = await load();
    await expect(svc.updateRoomService(5, {})).rejects.toMatchObject({ code: 'invalid_request' });
  });
});

describe('deleteRoomService', () => {
  it('deletes when no presence logs exist', async () => {
    const { svc, rq, pq } = await load();
    (rq.findRoomById as any).mockResolvedValue({ id_room: 5, name: 'Empty Lab' });
    (pq.countPresenceLogsForRoom as any).mockResolvedValue(0);
    await svc.deleteRoomService(5);
    expect(rq.deleteRoom).toHaveBeenCalledWith(5);
  });

  it('throws not_found when room missing', async () => {
    const { svc, rq } = await load();
    (rq.findRoomById as any).mockResolvedValue(null);
    await expect(svc.deleteRoomService(999)).rejects.toMatchObject({ code: 'not_found' });
  });

  it('throws conflict when presence logs exist', async () => {
    const { svc, rq, pq } = await load();
    (rq.findRoomById as any).mockResolvedValue({ id_room: 5, name: 'Active Lab' });
    (pq.countPresenceLogsForRoom as any).mockResolvedValue(42);
    await expect(svc.deleteRoomService(5)).rejects.toMatchObject({ code: 'conflict' });
    expect(rq.deleteRoom).not.toHaveBeenCalled();
  });
});
```

Also update the existing `vi.mock('../../src/db/queries/roomQueries.js', ...)` block near the top of the test file to include the new exports:

```ts
vi.mock('../../src/db/queries/roomQueries.js', () => ({
  listRooms: vi.fn(),
  findRoomById: vi.fn(),
  insertRoom: vi.fn(),
  updateRoomName: vi.fn(),
  deleteRoom: vi.fn(),
}));
```

And add a mock for the presenceQueries new export in the existing `vi.mock('../../src/db/queries/presenceQueries.js', ...)` block:

```ts
vi.mock('../../src/db/queries/presenceQueries.js', () => ({
  // ... existing entries ...
  countPresenceLogsForRoom: vi.fn(),
}));
```

Extend the `load()` helper at the top of the file so the tests can reach the presence query mock. If it currently returns `{ svc, rq, pq, uq, cfg }`, `pq` is already there. If not, add it.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/services/roomsService.test.ts`
Expected: FAIL — the three new service functions don't exist yet.

- [ ] **Step 3: Add the three new service functions to `src/services/roomsService.ts`**

Add these imports (add to the existing imports at the top):

```ts
import {
  listRooms,
  findRoomById,
  insertRoom,
  updateRoomName,
  deleteRoom,
} from '../db/queries/roomQueries.js';
import { countPresenceLogsForRoom, currentRoomPerUser, firstPingForUserInWindow } from '../db/queries/presenceQueries.js';
```

(Merge with existing imports rather than duplicating. `listRooms`, `findRoomById`, `currentRoomPerUser`, `firstPingForUserInWindow` are already imported; add `insertRoom`, `updateRoomName`, `deleteRoom`, `countPresenceLogsForRoom` to the existing import statements.)

Then append these three functions at the end of the file:

```ts
export async function createRoomService(input: { name: string }): Promise<{ id: number; name: string }> {
  const id = await insertRoom(input.name);
  const row = await findRoomById(id);
  if (!row) throw new AppError('internal_error', 'Room created but could not be read back');
  return { id: row.id_room, name: row.name };
}

export async function updateRoomService(
  id: number,
  patch: { name?: string },
): Promise<{ id: number; name: string }> {
  if (Object.keys(patch).length === 0) {
    throw new AppError('invalid_request', 'Empty patch');
  }
  const existing = await findRoomById(id);
  if (!existing) throw new AppError('not_found', 'Room not found');
  if (patch.name !== undefined) {
    await updateRoomName(id, patch.name);
  }
  const fresh = await findRoomById(id);
  if (!fresh) throw new AppError('internal_error', 'Room updated but could not be read back');
  return { id: fresh.id_room, name: fresh.name };
}

export async function deleteRoomService(id: number): Promise<void> {
  const existing = await findRoomById(id);
  if (!existing) throw new AppError('not_found', 'Room not found');
  const logCount = await countPresenceLogsForRoom(id);
  if (logCount > 0) {
    throw new AppError('conflict', `Cannot delete room with recorded presence — has ${logCount} log entries`);
  }
  await deleteRoom(id);
}
```

- [ ] **Step 4: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/services/roomsService.test.ts`
Expected: PASS. All new + existing tests green.

- [ ] **Step 5: Commit**

```bash
git add Aegis-Backend/src/services/roomsService.ts Aegis-Backend/tests/services/roomsService.test.ts
git commit -m "feat(rooms): add createRoom, updateRoom, deleteRoom services with presence-log guard"
```

---

## Task 4: Extend `admin/rooms.ts` router with POST, PATCH, DELETE

**Files:**
- Modify: `Aegis-Backend/src/routes/admin/rooms.ts`
- Modify: `Aegis-Backend/tests/routes/adminRooms.test.ts`

**Interfaces:**
- Consumes: `createRoomService`, `updateRoomService`, `deleteRoomService` from `roomsService`; `AppError`; `requireAuth`, `requireRole`.
- Produces: 3 new endpoints on the existing `adminRoomsRouter`:
  - `POST /` → 201 with the created room
  - `PATCH /:room_id` → 200 with updated room
  - `DELETE /:room_id` → 204

- [ ] **Step 1: Write failing test cases in `tests/routes/adminRooms.test.ts`**

Append these new `describe` blocks after the existing ones. Also update the existing `vi.mock('../../src/services/roomsService.js', ...)` block to include the new exports:

```ts
vi.mock('../../src/services/roomsService.js', () => ({
  listAllRooms: vi.fn(),
  getRoomMap: vi.fn(),
  getRoomCurrentOccupants: vi.fn(),
  getRoomAdditionalData: vi.fn(),
  createRoomService: vi.fn(),
  updateRoomService: vi.fn(),
  deleteRoomService: vi.fn(),
}));
```

New test blocks:

```ts
describe('POST /api/v1/admin/rooms', () => {
  it('returns 201 with the created room', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/roomsService.js');
    (svc.createRoomService as any).mockResolvedValue({ id: 5, name: 'Lab X' });
    const res = await request(app)
      .post('/api/v1/admin/rooms')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Lab X' });
    expect(res.status).toBe(201);
    expect(res.body).toEqual({ id: 5, name: 'Lab X' });
    expect(svc.createRoomService).toHaveBeenCalledWith({ name: 'Lab X' });
  });

  it('rejects missing name with 400', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .post('/api/v1/admin/rooms')
      .set('Authorization', `Bearer ${token}`)
      .send({});
    expect(res.status).toBe(400);
  });

  it('rejects unknown keys (strict) with 400', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .post('/api/v1/admin/rooms')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Lab X', extra: 'bad' });
    expect(res.status).toBe(400);
  });

  it('rejects name > 100 chars with 400', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .post('/api/v1/admin/rooms')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'x'.repeat(101) });
    expect(res.status).toBe(400);
  });
});

describe('PATCH /api/v1/admin/rooms/:room_id', () => {
  it('returns 200 with updated room', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/roomsService.js');
    (svc.updateRoomService as any).mockResolvedValue({ id: 5, name: 'Lab X (renamed)' });
    const res = await request(app)
      .patch('/api/v1/admin/rooms/5')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Lab X (renamed)' });
    expect(res.status).toBe(200);
    expect(res.body.name).toBe('Lab X (renamed)');
  });

  it('returns 404 when room missing', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/roomsService.js');
    const { AppError } = await import('../../src/lib/errors.js');
    (svc.updateRoomService as any).mockRejectedValue(new AppError('not_found'));
    const res = await request(app)
      .patch('/api/v1/admin/rooms/999')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'X' });
    expect(res.status).toBe(404);
  });

  it('rejects empty body with 400', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .patch('/api/v1/admin/rooms/5')
      .set('Authorization', `Bearer ${token}`)
      .send({});
    // Route layer accepts empty body but service throws invalid_request.
    // For symmetry, the service mock must throw or the route must catch.
    // We assert the response reflects the eventual 400 either way.
    const svc = await import('../../src/services/roomsService.js');
    (svc.updateRoomService as any).mockRejectedValue(
      new (await import('../../src/lib/errors.js')).AppError('invalid_request'),
    );
    const res2 = await request(app)
      .patch('/api/v1/admin/rooms/5')
      .set('Authorization', `Bearer ${token}`)
      .send({});
    expect(res2.status).toBe(400);
  });
});

describe('DELETE /api/v1/admin/rooms/:room_id', () => {
  it('returns 204 on success', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/roomsService.js');
    (svc.deleteRoomService as any).mockResolvedValue(undefined);
    const res = await request(app)
      .delete('/api/v1/admin/rooms/5')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(204);
    expect(svc.deleteRoomService).toHaveBeenCalledWith(5);
  });

  it('returns 409 when presence logs exist', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/roomsService.js');
    const { AppError } = await import('../../src/lib/errors.js');
    (svc.deleteRoomService as any).mockRejectedValue(new AppError('conflict'));
    const res = await request(app)
      .delete('/api/v1/admin/rooms/5')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(409);
  });

  it('returns 404 when room missing', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/roomsService.js');
    const { AppError } = await import('../../src/lib/errors.js');
    (svc.deleteRoomService as any).mockRejectedValue(new AppError('not_found'));
    const res = await request(app)
      .delete('/api/v1/admin/rooms/999')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/routes/adminRooms.test.ts`
Expected: FAIL — new handlers don't exist.

- [ ] **Step 3: Add the three new handlers to `src/routes/admin/rooms.ts`**

Update imports:

```ts
import {
  listAllRooms,
  getRoomMap,
  getRoomCurrentOccupants,
  getRoomAdditionalData,
  createRoomService,
  updateRoomService,
  deleteRoomService,
} from '../../services/roomsService.js';
```

Add these schemas near the top of the file (after `const idParam = ...`):

```ts
const createBodySchema = z.object({
  name: z.string().min(1).max(100),
}).strict();

const patchBodySchema = z.object({
  name: z.string().min(1).max(100).optional(),
}).strict();
```

Add the three handlers at the end of the file, before the export line if any (there is none — the router is already declared as `export const adminRoomsRouter`):

```ts
adminRoomsRouter.post('/', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = createBodySchema.safeParse(req.body);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    const room = await createRoomService(parsed.data);
    res.status(201).json(room);
  } catch (err) {
    next(err);
  }
});

adminRoomsRouter.patch('/:room_id', requireAuth, requireRole('admin'), async (req, res, next) => {
  const idParsed = idParam.safeParse(req.params);
  if (!idParsed.success) return next(new AppError('invalid_request'));
  const bodyParsed = patchBodySchema.safeParse(req.body);
  if (!bodyParsed.success) return next(new AppError('invalid_request'));
  try {
    const room = await updateRoomService(idParsed.data.room_id, bodyParsed.data);
    res.json(room);
  } catch (err) {
    next(err);
  }
});

adminRoomsRouter.delete('/:room_id', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = idParam.safeParse(req.params);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    await deleteRoomService(parsed.data.room_id);
    res.status(204).end();
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
git commit -m "feat(admin): add POST/PATCH/DELETE handlers to /admin/rooms"
```

---

## Task 5: `beaconsService` — full CRUD

**Files:**
- Create: `Aegis-Backend/src/services/beaconsService.ts`
- Create: `Aegis-Backend/tests/services/beaconsService.test.ts`

**Interfaces:**
- Consumes: `findRoomById` (roomQueries); `listDevices`, `findDeviceById`, `findDeviceByIdentifier`, `insertDevice`, `updateDevice`, `deleteDevice`, `DeviceWithRoom` (deviceQueries); `AppError`.
- Produces:
  - `interface BeaconResource { id: number; name: string; beacon_identifier: string; room_id: number | null; room_name: string | null }`
  - `function toBeaconResource(row: DeviceWithRoom): BeaconResource`
  - `async function listBeaconsService(filter, page, perPage): Promise<{ list: BeaconResource[]; total: number; page: number; per_page: number }>`
  - `async function getBeaconService(id: number): Promise<BeaconResource>` — throws `not_found`
  - `async function createBeaconService(input: { name: string; beacon_identifier: string; room_id: number | null }): Promise<BeaconResource>` — throws `invalid_request` (unknown room), `conflict` (identifier taken)
  - `async function updateBeaconService(id: number, patch: { name?: string; beacon_identifier?: string; room_id?: number | null }): Promise<BeaconResource>` — throws `not_found`, `invalid_request`, `conflict`
  - `async function deleteBeaconService(id: number): Promise<void>` — throws `not_found`

- [ ] **Step 1: Write failing test `tests/services/beaconsService.test.ts`**

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
  insertRoom: vi.fn(),
  updateRoomName: vi.fn(),
  deleteRoom: vi.fn(),
}));

vi.mock('../../src/db/queries/deviceQueries.js', () => ({
  listAssignedDevices: vi.fn(),
  listDevices: vi.fn(),
  findDeviceById: vi.fn(),
  findDeviceByIdentifier: vi.fn(),
  insertDevice: vi.fn(),
  updateDevice: vi.fn(),
  deleteDevice: vi.fn(),
}));

const load = async () => {
  const svc = await import('../../src/services/beaconsService.js');
  const rq = await import('../../src/db/queries/roomQueries.js');
  const dq = await import('../../src/db/queries/deviceQueries.js');
  return { svc, rq, dq };
};

const deviceRow = {
  id_device: 1,
  name: 'iBeacon 1',
  identifier: '1:1000',
  id_room: 3,
  room_name: 'Lab 3.02',
};

const unassignedRow = {
  id_device: 2,
  name: 'iBeacon Spare',
  identifier: '1:9999',
  id_room: null,
  room_name: null,
};

beforeEach(() => vi.clearAllMocks());

describe('toBeaconResource', () => {
  it('maps id_device to id', async () => {
    const { svc } = await load();
    const r = svc.toBeaconResource(deviceRow);
    expect(r).toEqual({
      id: 1,
      name: 'iBeacon 1',
      beacon_identifier: '1:1000',
      room_id: 3,
      room_name: 'Lab 3.02',
    });
  });

  it('preserves null room fields for unassigned', async () => {
    const { svc } = await load();
    const r = svc.toBeaconResource(unassignedRow);
    expect(r.room_id).toBeNull();
    expect(r.room_name).toBeNull();
  });
});

describe('listBeaconsService', () => {
  it('returns paged list', async () => {
    const { svc, dq } = await load();
    (dq.listDevices as any).mockResolvedValue({ list: [deviceRow, unassignedRow], total: 2 });
    const r = await svc.listBeaconsService({}, 1, 20);
    expect(r.total).toBe(2);
    expect(r.list).toHaveLength(2);
    expect(r.page).toBe(1);
    expect(r.per_page).toBe(20);
  });
});

describe('getBeaconService', () => {
  it('returns resource for existing device', async () => {
    const { svc, dq } = await load();
    (dq.findDeviceById as any).mockResolvedValue(deviceRow);
    const r = await svc.getBeaconService(1);
    expect(r.id).toBe(1);
  });

  it('throws not_found when device missing', async () => {
    const { svc, dq } = await load();
    (dq.findDeviceById as any).mockResolvedValue(null);
    await expect(svc.getBeaconService(999)).rejects.toMatchObject({ code: 'not_found' });
  });
});

describe('createBeaconService', () => {
  it('creates an assigned beacon', async () => {
    const { svc, rq, dq } = await load();
    (rq.findRoomById as any).mockResolvedValue({ id_room: 3, name: 'Lab 3.02' });
    (dq.findDeviceByIdentifier as any).mockResolvedValue(null);
    (dq.insertDevice as any).mockResolvedValue(1);
    (dq.findDeviceById as any).mockResolvedValue(deviceRow);
    const r = await svc.createBeaconService({
      name: 'iBeacon 1',
      beacon_identifier: '1:1000',
      room_id: 3,
    });
    expect(r.id).toBe(1);
    expect(dq.insertDevice).toHaveBeenCalledWith({
      name: 'iBeacon 1',
      identifier: '1:1000',
      id_room: 3,
    });
  });

  it('creates an unassigned beacon (room_id null)', async () => {
    const { svc, dq } = await load();
    (dq.findDeviceByIdentifier as any).mockResolvedValue(null);
    (dq.insertDevice as any).mockResolvedValue(2);
    (dq.findDeviceById as any).mockResolvedValue(unassignedRow);
    const r = await svc.createBeaconService({
      name: 'iBeacon Spare',
      beacon_identifier: '1:9999',
      room_id: null,
    });
    expect(r.room_id).toBeNull();
    expect(dq.insertDevice).toHaveBeenCalledWith({
      name: 'iBeacon Spare',
      identifier: '1:9999',
      id_room: null,
    });
  });

  it('throws invalid_request when room_id refers to a missing room', async () => {
    const { svc, rq } = await load();
    (rq.findRoomById as any).mockResolvedValue(null);
    await expect(
      svc.createBeaconService({ name: 'x', beacon_identifier: 'y', room_id: 999 }),
    ).rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('throws conflict on duplicate identifier', async () => {
    const { svc, rq, dq } = await load();
    (rq.findRoomById as any).mockResolvedValue({ id_room: 3, name: 'Lab' });
    (dq.findDeviceByIdentifier as any).mockResolvedValue(deviceRow);
    await expect(
      svc.createBeaconService({ name: 'x', beacon_identifier: '1:1000', room_id: 3 }),
    ).rejects.toMatchObject({ code: 'conflict' });
  });
});

describe('updateBeaconService', () => {
  it('renames a beacon', async () => {
    const { svc, dq } = await load();
    (dq.findDeviceById as any)
      .mockResolvedValueOnce(deviceRow)
      .mockResolvedValueOnce({ ...deviceRow, name: 'iBeacon 1 (repaired)' });
    const r = await svc.updateBeaconService(1, { name: 'iBeacon 1 (repaired)' });
    expect(r.name).toBe('iBeacon 1 (repaired)');
    expect(dq.updateDevice).toHaveBeenCalledWith(1, { name: 'iBeacon 1 (repaired)' });
  });

  it('unassigns a beacon (room_id: null)', async () => {
    const { svc, dq } = await load();
    (dq.findDeviceById as any)
      .mockResolvedValueOnce(deviceRow)
      .mockResolvedValueOnce({ ...deviceRow, id_room: null, room_name: null });
    const r = await svc.updateBeaconService(1, { room_id: null });
    expect(r.room_id).toBeNull();
    expect(dq.updateDevice).toHaveBeenCalledWith(1, { id_room: null });
  });

  it('throws not_found when device missing', async () => {
    const { svc, dq } = await load();
    (dq.findDeviceById as any).mockResolvedValue(null);
    await expect(svc.updateBeaconService(999, { name: 'x' })).rejects.toMatchObject({ code: 'not_found' });
  });

  it('throws invalid_request on empty patch', async () => {
    const { svc } = await load();
    await expect(svc.updateBeaconService(1, {})).rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('throws invalid_request when new room_id refers to missing room', async () => {
    const { svc, dq, rq } = await load();
    (dq.findDeviceById as any).mockResolvedValue(deviceRow);
    (rq.findRoomById as any).mockResolvedValue(null);
    await expect(svc.updateBeaconService(1, { room_id: 999 })).rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('throws conflict when new identifier taken by another device', async () => {
    const { svc, dq } = await load();
    (dq.findDeviceById as any).mockResolvedValue(deviceRow);
    (dq.findDeviceByIdentifier as any).mockResolvedValue({ ...deviceRow, id_device: 99 });
    await expect(svc.updateBeaconService(1, { beacon_identifier: '1:2000' })).rejects.toMatchObject({ code: 'conflict' });
  });

  it('allows identifier update to same value (idempotent)', async () => {
    const { svc, dq } = await load();
    (dq.findDeviceById as any)
      .mockResolvedValueOnce(deviceRow)
      .mockResolvedValueOnce(deviceRow);
    (dq.findDeviceByIdentifier as any).mockResolvedValue(deviceRow);
    const r = await svc.updateBeaconService(1, { beacon_identifier: '1:1000' });
    expect(r.beacon_identifier).toBe('1:1000');
  });
});

describe('deleteBeaconService', () => {
  it('deletes existing device', async () => {
    const { svc, dq } = await load();
    (dq.findDeviceById as any).mockResolvedValue(deviceRow);
    await svc.deleteBeaconService(1);
    expect(dq.deleteDevice).toHaveBeenCalledWith(1);
  });

  it('throws not_found when device missing', async () => {
    const { svc, dq } = await load();
    (dq.findDeviceById as any).mockResolvedValue(null);
    await expect(svc.deleteBeaconService(999)).rejects.toMatchObject({ code: 'not_found' });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/services/beaconsService.test.ts`
Expected: FAIL — module `beaconsService.js` not found.

- [ ] **Step 3: Create `src/services/beaconsService.ts`**

```ts
import { AppError } from '../lib/errors.js';
import { findRoomById } from '../db/queries/roomQueries.js';
import {
  DeviceWithRoom,
  listDevices,
  findDeviceById,
  findDeviceByIdentifier,
  insertDevice,
  updateDevice,
  deleteDevice,
} from '../db/queries/deviceQueries.js';

export interface BeaconResource {
  id: number;
  name: string;
  beacon_identifier: string;
  room_id: number | null;
  room_name: string | null;
}

export function toBeaconResource(row: DeviceWithRoom): BeaconResource {
  return {
    id: row.id_device,
    name: row.name,
    beacon_identifier: row.identifier,
    room_id: row.id_room,
    room_name: row.room_name,
  };
}

export async function listBeaconsService(
  filter: { assigned?: boolean; roomId?: number },
  page: number,
  perPage: number,
): Promise<{ list: BeaconResource[]; total: number; page: number; per_page: number }> {
  const { list, total } = await listDevices(filter, page, perPage);
  return {
    list: list.map(toBeaconResource),
    total,
    page,
    per_page: perPage,
  };
}

export async function getBeaconService(id: number): Promise<BeaconResource> {
  const row = await findDeviceById(id);
  if (!row) throw new AppError('not_found', 'Device not found');
  return toBeaconResource(row);
}

export async function createBeaconService(input: {
  name: string;
  beacon_identifier: string;
  room_id: number | null;
}): Promise<BeaconResource> {
  if (input.room_id !== null) {
    const room = await findRoomById(input.room_id);
    if (!room) throw new AppError('invalid_request', 'Unknown room_id');
  }
  const dup = await findDeviceByIdentifier(input.beacon_identifier);
  if (dup) throw new AppError('conflict', 'beacon_identifier already exists');

  const id = await insertDevice({
    name: input.name,
    identifier: input.beacon_identifier,
    id_room: input.room_id,
  });
  const row = await findDeviceById(id);
  if (!row) throw new AppError('internal_error', 'Device created but could not be read back');
  return toBeaconResource(row);
}

export async function updateBeaconService(
  id: number,
  patch: { name?: string; beacon_identifier?: string; room_id?: number | null },
): Promise<BeaconResource> {
  if (Object.keys(patch).length === 0) {
    throw new AppError('invalid_request', 'Empty patch');
  }
  const existing = await findDeviceById(id);
  if (!existing) throw new AppError('not_found', 'Device not found');

  if (patch.room_id !== undefined && patch.room_id !== null) {
    const room = await findRoomById(patch.room_id);
    if (!room) throw new AppError('invalid_request', 'Unknown room_id');
  }

  if (patch.beacon_identifier !== undefined && patch.beacon_identifier !== existing.identifier) {
    const collide = await findDeviceByIdentifier(patch.beacon_identifier);
    if (collide && collide.id_device !== id) {
      throw new AppError('conflict', 'beacon_identifier already exists');
    }
  }

  // Translate the API-shaped patch to the DB-shaped patch.
  const dbPatch: { name?: string; identifier?: string; id_room?: number | null } = {};
  if (patch.name !== undefined) dbPatch.name = patch.name;
  if (patch.beacon_identifier !== undefined) dbPatch.identifier = patch.beacon_identifier;
  if (patch.room_id !== undefined) dbPatch.id_room = patch.room_id;

  await updateDevice(id, dbPatch);
  const fresh = await findDeviceById(id);
  if (!fresh) throw new AppError('internal_error', 'Device updated but could not be read back');
  return toBeaconResource(fresh);
}

export async function deleteBeaconService(id: number): Promise<void> {
  const existing = await findDeviceById(id);
  if (!existing) throw new AppError('not_found', 'Device not found');
  await deleteDevice(id);
}
```

- [ ] **Step 4: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/services/beaconsService.test.ts`
Expected: PASS — 15 tests.

- [ ] **Step 5: Type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add Aegis-Backend/src/services/beaconsService.ts Aegis-Backend/tests/services/beaconsService.test.ts
git commit -m "feat(beacons): add beaconsService with CRUD, uniqueness, and room validation"
```

---

## Task 6: `admin/beacons` router with 5 endpoints

**Files:**
- Create: `Aegis-Backend/src/routes/admin/beacons.ts`
- Create: `Aegis-Backend/tests/routes/adminBeacons.test.ts`

**Interfaces:**
- Consumes: `listBeaconsService`, `getBeaconService`, `createBeaconService`, `updateBeaconService`, `deleteBeaconService` from `beaconsService`; `AppError`; `requireAuth`, `requireRole`.
- Produces: `beaconsAdminRouter` — 5 endpoints under `/api/v1/admin/beacons`:
  - `GET /` — list, paged, filterable
  - `GET /:device_id` — one
  - `POST /` — create → 201
  - `PATCH /:device_id` — update → 200
  - `DELETE /:device_id` — delete → 204

- [ ] **Step 1: Write failing test `tests/routes/adminBeacons.test.ts`**

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

vi.mock('../../src/services/beaconsService.js', () => ({
  listBeaconsService: vi.fn(),
  getBeaconService: vi.fn(),
  createBeaconService: vi.fn(),
  updateBeaconService: vi.fn(),
  deleteBeaconService: vi.fn(),
  toBeaconResource: vi.fn(),
}));

const buildTestApp = async (role: 'admin' | 'learner' = 'admin', sub = 1) => {
  const { errorHandler } = await import('../../src/middleware/errorHandler.js');
  const { beaconsAdminRouter } = await import('../../src/routes/admin/beacons.js');
  const { signAccessToken } = await import('../../src/services/tokenService.js');
  const app = express();
  app.use(express.json());
  app.use('/api/v1/admin/beacons', beaconsAdminRouter);
  app.use(errorHandler);
  const token = signAccessToken({ sub, role });
  return { app, token };
};

beforeEach(() => vi.clearAllMocks());

describe('GET /api/v1/admin/beacons', () => {
  it('returns paged list', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    (svc.listBeaconsService as any).mockResolvedValue({
      list: [], total: 0, page: 1, per_page: 20,
    });
    const res = await request(app)
      .get('/api/v1/admin/beacons?page=1&per_page=20')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.total).toBe(0);
  });

  it('rejects learner with 403', async () => {
    const { app, token } = await buildTestApp('learner');
    const res = await request(app)
      .get('/api/v1/admin/beacons')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(403);
  });

  it('passes assigned=true correctly', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    (svc.listBeaconsService as any).mockResolvedValue({ list: [], total: 0, page: 1, per_page: 20 });
    await request(app)
      .get('/api/v1/admin/beacons?assigned=true')
      .set('Authorization', `Bearer ${token}`);
    expect(svc.listBeaconsService).toHaveBeenCalledWith(
      expect.objectContaining({ assigned: true }),
      1,
      20,
    );
  });

  it('passes assigned=false correctly', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    (svc.listBeaconsService as any).mockResolvedValue({ list: [], total: 0, page: 1, per_page: 20 });
    await request(app)
      .get('/api/v1/admin/beacons?assigned=false')
      .set('Authorization', `Bearer ${token}`);
    expect(svc.listBeaconsService).toHaveBeenCalledWith(
      expect.objectContaining({ assigned: false }),
      1,
      20,
    );
  });

  it('rejects invalid assigned value with 400', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .get('/api/v1/admin/beacons?assigned=yes')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });
});

describe('GET /api/v1/admin/beacons/:device_id', () => {
  it('returns 200 on success', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    (svc.getBeaconService as any).mockResolvedValue({ id: 1, name: 'iBeacon 1' });
    const res = await request(app)
      .get('/api/v1/admin/beacons/1')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.id).toBe(1);
  });

  it('returns 404 when device missing', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    const { AppError } = await import('../../src/lib/errors.js');
    (svc.getBeaconService as any).mockRejectedValue(new AppError('not_found'));
    const res = await request(app)
      .get('/api/v1/admin/beacons/999')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });

  it('rejects non-numeric id with 400', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .get('/api/v1/admin/beacons/abc')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
  });
});

describe('POST /api/v1/admin/beacons', () => {
  it('returns 201 with created beacon', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    (svc.createBeaconService as any).mockResolvedValue({ id: 1, name: 'iBeacon 1' });
    const res = await request(app)
      .post('/api/v1/admin/beacons')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'iBeacon 1', beacon_identifier: '1:1000', room_id: 3 });
    expect(res.status).toBe(201);
  });

  it('accepts room_id: null (unassigned)', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    (svc.createBeaconService as any).mockResolvedValue({ id: 2, name: 'Spare' });
    const res = await request(app)
      .post('/api/v1/admin/beacons')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Spare', beacon_identifier: '1:9999', room_id: null });
    expect(res.status).toBe(201);
    expect(svc.createBeaconService).toHaveBeenCalledWith({
      name: 'Spare', beacon_identifier: '1:9999', room_id: null,
    });
  });

  it('returns 409 on conflict', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    const { AppError } = await import('../../src/lib/errors.js');
    (svc.createBeaconService as any).mockRejectedValue(new AppError('conflict'));
    const res = await request(app)
      .post('/api/v1/admin/beacons')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'x', beacon_identifier: '1:1000', room_id: 3 });
    expect(res.status).toBe(409);
  });

  it('rejects unknown keys with 400 (strict)', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .post('/api/v1/admin/beacons')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'x', beacon_identifier: '1:1000', room_id: 3, extra: 'bad' });
    expect(res.status).toBe(400);
  });

  it('rejects missing required fields with 400', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .post('/api/v1/admin/beacons')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'x' });
    expect(res.status).toBe(400);
  });
});

describe('PATCH /api/v1/admin/beacons/:device_id', () => {
  it('returns 200 with updated beacon', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    (svc.updateBeaconService as any).mockResolvedValue({ id: 1, name: 'renamed' });
    const res = await request(app)
      .patch('/api/v1/admin/beacons/1')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'renamed' });
    expect(res.status).toBe(200);
    expect(svc.updateBeaconService).toHaveBeenCalledWith(1, { name: 'renamed' });
  });

  it('accepts room_id: null in patch', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    (svc.updateBeaconService as any).mockResolvedValue({ id: 1, room_id: null });
    const res = await request(app)
      .patch('/api/v1/admin/beacons/1')
      .set('Authorization', `Bearer ${token}`)
      .send({ room_id: null });
    expect(res.status).toBe(200);
    expect(svc.updateBeaconService).toHaveBeenCalledWith(1, { room_id: null });
  });

  it('rejects unknown keys with 400', async () => {
    const { app, token } = await buildTestApp();
    const res = await request(app)
      .patch('/api/v1/admin/beacons/1')
      .set('Authorization', `Bearer ${token}`)
      .send({ id_device: 99 });
    expect(res.status).toBe(400);
  });
});

describe('DELETE /api/v1/admin/beacons/:device_id', () => {
  it('returns 204 on success', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    (svc.deleteBeaconService as any).mockResolvedValue(undefined);
    const res = await request(app)
      .delete('/api/v1/admin/beacons/1')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(204);
  });

  it('returns 404 when device missing', async () => {
    const { app, token } = await buildTestApp();
    const svc = await import('../../src/services/beaconsService.js');
    const { AppError } = await import('../../src/lib/errors.js');
    (svc.deleteBeaconService as any).mockRejectedValue(new AppError('not_found'));
    const res = await request(app)
      .delete('/api/v1/admin/beacons/999')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(404);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/routes/adminBeacons.test.ts`
Expected: FAIL — router module doesn't exist.

- [ ] **Step 3: Create `src/routes/admin/beacons.ts`**

```ts
import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../middleware/requireAuth.js';
import { requireRole } from '../../middleware/requireRole.js';
import { AppError } from '../../lib/errors.js';
import {
  listBeaconsService,
  getBeaconService,
  createBeaconService,
  updateBeaconService,
  deleteBeaconService,
} from '../../services/beaconsService.js';

const idParam = z.object({ device_id: z.coerce.number().int().positive() });

const listQuerySchema = z.object({
  assigned: z
    .enum(['true', 'false'])
    .optional()
    .transform((v) => (v === undefined ? undefined : v === 'true')),
  room_id: z.coerce.number().int().positive().optional(),
  page: z.coerce.number().int().min(1).default(1),
  per_page: z.coerce.number().int().min(1).max(100).default(20),
});

const createBodySchema = z.object({
  name: z.string().min(1).max(100),
  beacon_identifier: z.string().min(1).max(100),
  room_id: z.number().int().positive().nullable(),
}).strict();

const patchBodySchema = z.object({
  name: z.string().min(1).max(100).optional(),
  beacon_identifier: z.string().min(1).max(100).optional(),
  room_id: z.number().int().positive().nullable().optional(),
}).strict();

export const beaconsAdminRouter = Router();

beaconsAdminRouter.get('/', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = listQuerySchema.safeParse(req.query);
  if (!parsed.success) return next(new AppError('invalid_request'));
  const { assigned, room_id, page, per_page } = parsed.data;
  try {
    const result = await listBeaconsService(
      { assigned, roomId: room_id },
      page,
      per_page,
    );
    res.json(result);
  } catch (err) {
    next(err);
  }
});

beaconsAdminRouter.get('/:device_id', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = idParam.safeParse(req.params);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    const beacon = await getBeaconService(parsed.data.device_id);
    res.json(beacon);
  } catch (err) {
    next(err);
  }
});

beaconsAdminRouter.post('/', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = createBodySchema.safeParse(req.body);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    const beacon = await createBeaconService(parsed.data);
    res.status(201).json(beacon);
  } catch (err) {
    next(err);
  }
});

beaconsAdminRouter.patch('/:device_id', requireAuth, requireRole('admin'), async (req, res, next) => {
  const idParsed = idParam.safeParse(req.params);
  if (!idParsed.success) return next(new AppError('invalid_request'));
  const bodyParsed = patchBodySchema.safeParse(req.body);
  if (!bodyParsed.success) return next(new AppError('invalid_request'));
  try {
    const beacon = await updateBeaconService(idParsed.data.device_id, bodyParsed.data);
    res.json(beacon);
  } catch (err) {
    next(err);
  }
});

beaconsAdminRouter.delete('/:device_id', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = idParam.safeParse(req.params);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    await deleteBeaconService(parsed.data.device_id);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});
```

- [ ] **Step 4: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/routes/adminBeacons.test.ts`
Expected: PASS — 15 tests.

- [ ] **Step 5: Type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add Aegis-Backend/src/routes/admin/beacons.ts Aegis-Backend/tests/routes/adminBeacons.test.ts
git commit -m "feat(admin): add /admin/beacons router with 5 CRUD endpoints"
```

---

## Task 7: Mount `beaconsAdminRouter` in `app.ts`

**Files:**
- Modify: `Aegis-Backend/src/app.ts`

**Interfaces:**
- Consumes: `beaconsAdminRouter` from `routes/admin/beacons.ts`.
- Produces: `/api/v1/admin/beacons/*` becomes a live mount.

- [ ] **Step 1: Add the import + mount to `src/app.ts`**

Add this import alongside the other admin router imports:

```ts
import { beaconsAdminRouter } from './routes/admin/beacons.js';
```

Then add the mount in the admin group, right after `usersRouter`:

```ts
  app.use('/api/v1/admin/beacons', beaconsAdminRouter);
```

The full admin block should look like:

```ts
  app.use('/api/v1/admin/absence-summary', absenceSummaryRouter);
  app.use('/api/v1/admin/overview', adminOverviewRouter);
  app.use('/api/v1/admin/rooms', adminRoomsRouter);
  app.use('/api/v1/admin/session-config', sessionConfigRouter);
  app.use('/api/v1/admin/system-config', systemConfigRouter);
  app.use('/api/v1/admin/rollup', rollupRouter);
  app.use('/api/v1/admin/users', usersRouter);
  app.use('/api/v1/admin/beacons', beaconsAdminRouter);
```

- [ ] **Step 2: Type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 3: Full test suite**

Run: `cd Aegis-Backend && npm test`
Expected: all tests pass. Total count grows by the new tests: baseline (149 after main merges) + roomsService additions (7) + adminRooms additions (10) + beaconsService (15) + adminBeacons (15) ≈ ~196 tests. Exact number depends on baseline drift; the important thing is no failures.

- [ ] **Step 4: Lint**

Run: `cd Aegis-Backend && npm run lint`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add Aegis-Backend/src/app.ts
git commit -m "feat(app): mount /admin/beacons router"
```

---

## Task 8: Final integration checks

**Files:** none new; verification only.

- [ ] **Step 1: Full type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 2: Full test suite**

Run: `cd Aegis-Backend && npm test`
Expected: all tests pass; count around 196.

- [ ] **Step 3: Lint**

Run: `cd Aegis-Backend && npm run lint`
Expected: exit 0.

- [ ] **Step 4: Verify all mounts are unique**

Run: `grep -E "app.use\('/api/v1" Aegis-Backend/src/app.ts | sort`
Expected: 13 distinct paths; `/api/v1/admin/beacons` appears exactly once.

---

## Verification checklist (post-implementation)

- All new tests pass; full suite passes; tsc clean; lint clean.
- `POST /api/v1/admin/rooms` with `{name: "New Lab"}` returns 201 with `{id, name}`.
- `PATCH /api/v1/admin/rooms/:id` renames a room; 404 on unknown; 400 on empty body.
- `DELETE /api/v1/admin/rooms/:id` returns 204 for an empty room; 409 for a room with presence logs; 404 for unknown.
- `GET /api/v1/admin/beacons?page=1&per_page=20` returns paged list including unassigned devices.
- `GET /api/v1/admin/beacons?assigned=false` returns only unassigned; `?assigned=true` returns only assigned.
- `POST /api/v1/admin/beacons` with `{name, beacon_identifier, room_id: null}` creates an unassigned beacon.
- `POST /api/v1/admin/beacons` with a duplicate `beacon_identifier` returns 409.
- `POST /api/v1/admin/beacons` with an unknown `room_id` returns 400.
- `PATCH /api/v1/admin/beacons/:id` with `{room_id: null}` unassigns a beacon.
- `DELETE /api/v1/admin/beacons/:id` returns 204; 404 for unknown.
- Learner-facing `GET /api/v1/beacons` still returns `{list: [{beacon_identifier, room_id, room_name}]}` — same shape as before.
