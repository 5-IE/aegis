# Aegis — Product Requirements Document (PRD)

**Status:** Recap of the delivered product with forward-looking requirements.
**Related:** [Product Overview](product-overview.md) · [Architecture](architecture.md)

This PRD documents what Aegis is meant to do and against which the current build
is measured. Requirements are tagged **[Done]**, **[Partial]**, or **[Planned]**
to reflect reality as of this writing.

---

## 1. Goal

Record academy attendance **passively and trustworthily**: a learner is marked
present by walking past a classroom beacon, without manual check-in, and admins
get real-time and historical attendance they can rely on.

## 2. Non-goals

- Not a general LMS, grading, or scheduling system — attendance only.
- Not a public/multi-tenant SaaS — a single first-party academy deployment.
- Not a payments, messaging, or content platform.
- No localization beyond English for the MVP (internal administrative tool).

## 3. Personas

| Persona | Platform | Primary needs |
|---|---|---|
| **Learner** | iPhone | Automatic attendance; view own dashboard + history; one-time device binding. |
| **Admin / instructor** | macOS | Live room occupancy; roster with today's status; manage rooms/beacons/users; configure session windows; daily reports. |

## 4. Functional requirements

### 4.1 Authentication & accounts
- **[Done]** Username + password login returning a short-lived JWT access token
  (15 min) and a rotating opaque refresh token (30 days), password hashed with
  bcrypt.
- **[Done]** Refresh-token rotation with reuse detection (a replayed refresh
  revokes the whole chain).
- **[Done]** Role-based access: `learner` vs `admin`.
- **[Done]** Admin user management: create, list, update, reset password,
  deactivate (no self-delete), reactivate.

### 4.2 Device binding & trust
- **[Done]** A learner registers a device public key (`POST /register-device`).
- **[Done]** `POST /api/v1/presence` requires a valid P-256 ECDSA signature over
  a canonical `METHOD\nPATH\nTIMESTAMP\nSHA256(body)` payload, verified against
  the stored key, within a ±60 s freshness window.
- **[Done]** Client signing on iOS (Secure Enclave key, X9.63 public export,
  request signing wired into the HTTP layer).
- **[Planned]** Registration screen surfaced in the normal app launch flow.

### 4.3 Presence & attendance
- **[Done]** Presence ingestion: store `room_id`, optional `position_x/y` and
  `battery_level` per ping, validated against existing rooms.
- **[Done]** Live status per learner: `Not Checked In` / `Running Late` /
  `Checked In` / `Checked Out` / `Not Checked Out` / `Off`, computed against
  configurable session windows and a staleness threshold, in a configurable
  timezone.
- **[Done]** Nightly rollup into one `ATTENDANCE_HISTORY` row per learner per
  day with status `early` / `late` / `absent` / `leave`; `leave` is preserved
  (not overwritten). Runnable on cron and on-demand via admin endpoint.
- **[Done]** Learner dashboard totals + today's status; paginated attendance
  history with month/year filter.
- **[Partial]** End-to-end passive capture — the phone does not yet **detect**
  beacons or **trigger** a presence send; the send/sign/ingest path it feeds is
  built. See §4.6.

### 4.4 Admin operations
- **[Done]** Live absence summary (present / late / absent / no-clock-in counts).
- **[Done]** Roster overview with today's status, filterable by name/session.
- **[Done]** Room CRUD; live radar per room (map + current occupants + metrics).
- **[Done]** Beacon CRUD and room assignment.
- **[Done]** Session-window config (AM/PM start / late-after / end) and system
  config (staleness minutes, timezone).

### 4.5 Beacon hardware
- **[Done]** ESP32 firmware advertising a standard iBeacon packet, rotating the
  minor value every 5 minutes to resist trivial cloning.

### 4.6 Passive detection (the remaining loop)
- **[Planned]** CoreLocation region monitoring / ranging on the learner app to
  detect nearby beacons in the background.
- **[Planned]** Beacon→room resolution on device and a trigger that calls the
  existing `sendPresence(...)`.
- **[Planned]** On-device trilateration (non-linear least squares) across
  multiple beacons to compute `position_x` / `position_y`.

## 5. Non-functional requirements

- **Security:** JWT on all protected routes; device signature on presence;
  bcrypt passwords; parameterized SQL (mysql2); input validation via zod; rate
  limiting on auth and presence.
- **Privacy:** collect only what's needed — credentials, location authorization
  (Always, for background detection), Bluetooth (via CoreLocation), optional
  battery level. No contacts/photos/camera/health/motion.
- **Performance:** presence writes are single-row inserts; config reads cached
  30 s; rollup is a batched nightly job.
- **Reliability:** refresh-token transactions use row locking to avoid
  double-rotation; rollup is idempotent and DST-safe.
- **Portability:** backend runs as a single Node process against MySQL 8 (native
  or containerized).

## 6. Success criteria

- A learner walking past a registered beacon is recorded present without manual
  action, and sees it reflected in their dashboard. *(Blocked only on §4.6.)*
- An admin sees live occupancy and an accurate daily roster.
- A forged or replayed presence request (wrong device, tampered body, stale
  timestamp) is rejected. *(Met — verified in backend tests and cross-language
  signing checks.)*

## 7. Out of scope / accepted limitations

- iBeacon advertisements are unauthenticated; device signing proves the enrolled
  *device*, not physical proximity. A sufficiently motivated learner running a
  modified client could submit fabricated room presence. Mitigation paths
  (custom BLE firmware with rotating secrets, or a checkpoint reader) are noted
  but out of scope for v1.
- No CI pipeline or container/compose orchestration yet (**[Planned]** ops work).
