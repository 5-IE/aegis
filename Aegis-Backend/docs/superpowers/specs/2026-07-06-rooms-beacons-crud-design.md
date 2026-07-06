# Aegis Backend — Admin Rooms + Beacons CRUD Design

**Date:** 2026-07-06
**Status:** Approved for implementation planning
**Scope:** Admin CRUD for `ROOM` and `DEVICE` (iBeacon) tables. 8 new endpoints, no new tables, no migration.
**Depends on:** existing schema (0001–0006) and existing admin patterns.

## Goal

Give admins the ability to manage classrooms and iBeacon devices via the API — create, read, update, delete. Today rooms and beacons can only be inserted via the seed script or SQL; admin apps need a UI for provisioning new rooms as the deployment grows.

## Non-goals for v1

- Self-service by learners (learners can only read `/beacons`, not modify)
- Bulk import (add later if provisioning many beacons becomes painful)
- Soft delete on ROOM/DEVICE (hard delete is fine — infrastructure resources, not user accounts)
- Historical audit of who created/deleted a room
- Device provisioning workflows (e.g. auto-register when a beacon first pings)

## Data model changes

**None.** Existing schema is sufficient:

```sql
CREATE TABLE `ROOM` (
  `id_room` INT AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(100) NOT NULL
);

CREATE TABLE `DEVICE` (
  `id_device` INT AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(100) NOT NULL,
  `identifier` VARCHAR(100) NOT NULL UNIQUE,
  `id_room` INT,
  FOREIGN KEY (`id_room`) REFERENCES `ROOM`(`id_room`) ON DELETE SET NULL
);
```

Key existing FK behaviors we rely on:
- `DEVICE.id_room ON DELETE SET NULL` — deleting a room orphans its beacons (they become "unassigned")
- `PRESENCE_LOG.id_room ON DELETE CASCADE` — deleting a room wipes its attendance history

The second one is why we need a **delete guard on rooms** (see A2 below).

## Endpoint catalogue

All under `/api/v1/admin`. Every endpoint requires `requireAuth` + `requireRole('admin')`.

### Rooms (4 endpoints — 1 existing, 3 new)

| # | Method | Path | Status | Purpose |
|---|---|---|---|---|
| R1 | GET | `/admin/rooms` | **already exists** | List all rooms (used by live radar) |
| R2 | POST | `/admin/rooms` | new | Create a room |
| R3 | PATCH | `/admin/rooms/:room_id` | new | Rename a room |
| R4 | DELETE | `/admin/rooms/:room_id` | new | Delete a room (guarded) |

### Beacons (4 endpoints — all new)

| # | Method | Path | Purpose |
|---|---|---|---|
| B1 | GET | `/admin/beacons` | Paged list of all devices (assigned + unassigned) |
| B2 | POST | `/admin/beacons` | Create a device (with optional room assignment) |
| B3 | PATCH | `/admin/beacons/:device_id` | Rename, change identifier, or reassign room |
| B4 | DELETE | `/admin/beacons/:device_id` | Delete a device (no guard — hardware can vanish freely) |

**Note:** Learner-facing `GET /api/v1/beacons` is untouched. That endpoint returns only assigned devices in a compact shape for iPhone caching. The new `/admin/beacons` is admin-scoped and returns the full device shape with pagination.

## Endpoint details

### R2 — POST /api/v1/admin/rooms

**Auth:** admin.

**Request body (strict):**
```json
{ "name": "Lab 3.02" }
```

**Validation:**
- `name`: string, 1–100 chars, required

No uniqueness constraint on `name` (two rooms can share a name if the org organizes by number elsewhere). If you want unique names later, add a DB constraint.

**Response 201:** the created room, matching `RoomResource`:
```json
{ "id": 5, "name": "Lab 3.02" }
```

**Errors:**
- 400 `invalid_request` — body malformed
- 409 not applicable (no uniqueness)

### R3 — PATCH /api/v1/admin/rooms/:room_id

**Auth:** admin.

**Path param:** `room_id` positive integer.

**Request body (strict, all optional but at least one required):**
```json
{ "name": "Lab 3.02 (renamed)" }
```

**Validation:**
- `name`: string, 1–100 chars, if present
- Empty body → 400 `invalid_request`

**Response 200:** the updated room.

**Errors:**
- 400 `invalid_request` — empty patch, malformed body, or unknown key
- 404 `not_found` — room does not exist

### R4 — DELETE /api/v1/admin/rooms/:room_id

**Auth:** admin.

**Behavior:**
1. 404 `not_found` if room missing.
2. **Guard:** query `SELECT COUNT(*) FROM PRESENCE_LOG WHERE id_room = ?`. If > 0, return 409 `conflict` with message "Cannot delete room with recorded presence — has N log entries". Prevents accidental history nukes.
3. Otherwise: `DELETE FROM ROOM WHERE id_room = ?`. FK cascade sets `DEVICE.id_room = NULL` for orphans; no history to cascade because we checked.
4. Return 204.

**Response:** 204 No Content.

**Errors:**
- 404 `not_found`
- 409 `conflict` — room has presence log entries

**Rationale:** Rooms accumulate a lot of downstream data (presence logs, attendance history via user). A hard delete without checking wipes historical attendance records — a mistake an admin would regret. Requiring an explicit workflow (delete the presence logs first, or don't delete the room) prevents that. Beacons don't need the same guard; they're physical devices that get replaced, and their downstream data (`PRESENCE_LOG.id_room`) is keyed off room, not device.

### B1 — GET /api/v1/admin/beacons

**Auth:** admin.

**Query parameters:**

| Param | Type | Notes |
|---|---|---|
| `assigned?` | boolean | `true` → only devices with a room; `false` → only unassigned; omit → all |
| `room_id?` | integer | Filter to devices in one specific room |
| `page?` | integer | Default 1 |
| `per_page?` | integer | Default 20, max 100 |

**Ordering:** `id_device ASC`.

**Response 200:**
```json
{
  "list": [
    {
      "id": 1,
      "name": "iBeacon 1",
      "beacon_identifier": "1:1000",
      "room_id": 3,
      "room_name": "Lab 3.02"
    },
    {
      "id": 5,
      "name": "iBeacon Spare",
      "beacon_identifier": "1:9999",
      "room_id": null,
      "room_name": null
    }
  ],
  "page": 1,
  "per_page": 20,
  "total": 5
}
```

`room_name` is joined from `ROOM.name`; null when `room_id` is null.

**Note on field naming:** learner-facing `GET /api/v1/beacons` uses `beacon_identifier` (no `id`, no `name`). Admin surface keeps that field name for consistency but adds `id` and `name`. Client-side, admin apps should treat this as its own resource shape.

### B2 — POST /api/v1/admin/beacons

**Auth:** admin.

**Request body (strict):**
```json
{
  "name": "iBeacon 5",
  "beacon_identifier": "1:1004",
  "room_id": 3
}
```

**Validation:**
- `name`: string, 1–100 chars, required
- `beacon_identifier`: string, 1–100 chars, required, unique across ALL devices
- `room_id`: positive integer OR null, optional (null / omitted = unassigned)

**Behavior:**
1. If `room_id` is provided, verify the room exists — 400 `invalid_request` if not.
2. If `beacon_identifier` already exists — 409 `conflict`.
3. Insert row.

**Response 201:** the created device (with joined `room_name`).

**Errors:**
- 400 `invalid_request` — body malformed, or `room_id` doesn't exist
- 409 `conflict` — `beacon_identifier` already taken

### B3 — PATCH /api/v1/admin/beacons/:device_id

**Auth:** admin.

**Path param:** `device_id` positive integer.

**Request body (strict, all optional, at least one required):**
```json
{ "name": "iBeacon 5 (repaired)", "beacon_identifier": "1:1005", "room_id": 4 }
```

**Validation:**
- Same field constraints as B2 (each optional).
- Empty body → 400.
- If `beacon_identifier` changes, uniqueness re-checked.
- If `room_id` changes and is not null, room existence re-checked.
- Setting `room_id: null` explicitly is allowed (unassigns a beacon).

**Response 200:** the updated device.

**Errors:**
- 400 `invalid_request` — empty patch, malformed, or `room_id` doesn't exist
- 404 `not_found` — device doesn't exist
- 409 `conflict` — new `beacon_identifier` taken by another device

### B4 — DELETE /api/v1/admin/beacons/:device_id

**Auth:** admin.

**Behavior:**
1. 404 `not_found` if device missing.
2. `DELETE FROM DEVICE WHERE id_device = ?`. No cascades required — `DEVICE` isn't referenced by any FK.
3. Return 204.

No guard. Hardware physically stops working, gets stolen, or gets returned to a supplier — admins should be able to delete freely. Existing `PRESENCE_LOG` rows (which reference `id_room`, not `id_device`) are unaffected.

**Response:** 204 No Content.

**Errors:**
- 404 `not_found`

## Cross-cutting semantics

### Response shapes

**Room** (identical to existing `RoomResource` used by live radar):
```ts
{ id: number; name: string }
```

**Device (admin scope):**
```ts
{
  id: number;
  name: string;
  beacon_identifier: string;
  room_id: number | null;
  room_name: string | null;
}
```

Learner-facing `/api/v1/beacons` shape stays as `{ beacon_identifier, room_id, room_name }` — no `id`, no `name`. That's a compact shape for iPhone caching and shouldn't change.

### Effect on existing consumers

- `roomsService.listAllRooms()` — unchanged; still returns `[{id, name}]`
- `roomsService.getRoomMap`, `getRoomCurrentOccupants`, `getRoomAdditionalData` — unchanged; still look up rooms by id
- Learner `GET /api/v1/beacons` — unchanged; still filters assigned devices
- Nothing about presence ingestion, dashboard, or attendance rollup changes

### Concurrency

Delete guards on rooms are best-effort (there's a TOCTOU gap between the COUNT check and the DELETE). If a presence log arrives in the window between the two, the DELETE will cascade-nuke it. Acceptable for v1 — admin actions are low-frequency; a proper fix would need a serializable transaction, out of scope.

## Project layout additions

```
Aegis-Backend/
  src/
    routes/admin/
      rooms.ts              # MODIFY: currently exports live-radar routes; add POST/PATCH/DELETE
                            # or extract admin CRUD to a new file — see plan
      beacons.ts            # NEW: admin device CRUD (4 endpoints)
    services/
      roomsService.ts       # MODIFY: add createRoom, updateRoom, deleteRoom
      beaconsService.ts     # NEW: list/get/create/update/delete devices
    db/queries/
      roomQueries.ts        # MODIFY: add insertRoom, updateRoomName, deleteRoom, countPresenceLogsInRoom
      deviceQueries.ts      # MODIFY: add listDevices, findDeviceById, insertDevice, updateDevice, deleteDevice, findDeviceByIdentifier
  tests/
    services/
      roomsService.test.ts       # MODIFY: add CRUD test coverage
      beaconsService.test.ts     # NEW
    routes/
      adminRooms.test.ts         # MODIFY: add CRUD test coverage
      adminBeacons.test.ts       # NEW
```

**Decision on router structure:** the existing `src/routes/admin/rooms.ts` exports `adminRoomsRouter` which mounts nested paths (`/`, `/:id/map`, `/:id/current-occupants`, `/:id/additional-data`). Adding POST at `/`, PATCH at `/:room_id`, DELETE at `/:room_id` fits cleanly there without refactoring. Keep it in the same file.

## Dependencies

No new runtime dependencies.

## Rate limits

None for v1. Admin surface, low volume.

## Config

No new config keys.

## Testing

- Unit tests: services with mocked queries.
- Route tests: supertest against the assembled router; service mocked.
- Coverage for each endpoint's happy path plus:
  - Room create: name too long → 400
  - Room delete: presence-log guard fires → 409
  - Room delete: no logs → 204
  - Beacon create: unknown room_id → 400
  - Beacon create: duplicate identifier → 409
  - Beacon patch: room_id=null unassigns
  - Beacon list: assigned filter
  - Every endpoint: learner token → 403

Integration tests against real MySQL still deferred.

## Migration order

No migration needed. Schema unchanged.

## Known limitations

- Room delete guard is TOCTOU-prone (see Concurrency above). Acceptable at admin-action volumes.
- No audit of who deleted what.
- Device `identifier` is validated as any 1–100 char string; the iBeacon format `major:minor` isn't enforced. Kept loose so the field can also accept UUIDs or vendor-specific IDs later without schema change.
- `room_id: null` in device PATCH must be explicit — `undefined`/omitted means "don't change." Zod's `.optional().nullable()` handles this via three-state logic; the plan spells it out.
