# Aegis — Product Requirements Document v1

**Date:** 2026-07-09 · **Status:** Reflects the shipped product state

---

## 1. What Aegis Is

Aegis is a **passive IoT attendance system** for a physical academy. Learners carry their iPhone; beacons in each classroom detect their presence. The system records attendance automatically — no manual check-in, no tap, no scan. Admins see who's where in real time and get daily attendance reports.

## 2. The Problem

Manual attendance is slow, error-prone, and gameable. Students can sign a sheet and leave, or arrive late unnoticed. Automated solutions (QR codes, NFC taps) still require a deliberate action and can be proxied. Aegis uses continuous passive proximity to provide high-confidence attendance with zero learner effort.

## 3. Users

| Role | Platform | Core need |
|------|----------|-----------|
| **Learner** | iPhone | Attendance happens invisibly; can see their own status and history |
| **Admin / Instructor** | macOS | Live room occupancy; roster and daily reports; manage the system |

## 4. System Architecture

```
┌────────────┐     BLE iBeacon     ┌────────────┐    POST /presence    ┌─────────────┐
│  ESP32     │ ─────────────────→  │  Learner   │ ──────────────────→  │   Backend   │
│  Beacon    │   (rotating minor)  │  iPhone    │   (device-signed)    │  (Node/TS)  │
└────────────┘                     └────────────┘                      └──────┬──────┘
                                                                              │
                                        ┌─────────────────────────────────────┤
                                        ▼                                     ▼
                                  ┌──────────┐                         ┌──────────┐
                                  │  Admin   │  ← REST API (JWT) →     │  MySQL   │
                                  │  macOS   │                         │    DB    │
                                  └──────────┘                         └──────────┘
```

## 5. Features

### 5.1 Authentication & Accounts

- Username/password login → short-lived JWT (15 min) + rotating opaque refresh token (30 days)
- Refresh-token reuse detection (replayed token revokes the whole chain)
- Role-based access: `learner` vs `admin`
- Admin CRUD on user accounts (create, edit, deactivate, reactivate, password reset)
- Learner sign-out and session expiry recovery

### 5.2 Device Binding & Trust

- One-time device registration: learner's iPhone generates a P-256 key pair in the Secure Enclave and uploads the public key (`POST /register-device`)
- Every `POST /presence` is signed with the device's private key (ECDSA over `METHOD\nPATH\nTIMESTAMP\nSHA256(body)`) — the backend verifies against the stored public key within a ±60s freshness window
- Raises the trust bar from "anyone with a token" to "the physical registered device"

### 5.3 Presence & Attendance

- **Ingestion:** each ping stores `room_id`, optional `position_x/y` (normalized 0–1), optional `battery_level`
- **Live status** per learner: `Not Checked In` / `Running Late` / `Checked In` / `Checked Out` / `Not Checked Out` / `Off` — computed against configurable session windows (AM/PM) and a staleness threshold, all in a configurable timezone
- **Nightly rollup:** collapses raw pings into one `ATTENDANCE_HISTORY` record per learner per date (`early` / `late` / `absent` / `leave`). Idempotent, DST-safe, respects manually-set leave. Runs via cron or on-demand from the admin app.
- **Reports:** admin can pull attendance aggregates for any ≤92-day range (attendance rate, late/absent counts per learner) as JSON summary or downloadable CSV

### 5.4 Learner App (iOS)

- Login with session persistence and token refresh
- Device registration flow (one-time, gates access to Home)
- Dashboard: today's attendance status (derived from API), total attendance / late / leave counts
- Attendance history with month/year filter
- Sign-out
- **Planned:** CoreLocation beacon detection → automatic presence reporting (the send/sign/ingest path is built; the sensing trigger is not)

### 5.5 Admin App (macOS)

- Login with coalesced token refresh (session survives >15 min, handles concurrent requests)
- **Dashboard:** absence summary cards, daily attendance overview table with pagination, name search, session filter
- **Live Radar:** per-room real-time map of learner positions + beacon markers (from admin-configured positions); current occupants table; people-in-room metric; 5-second polling with 3-strike error tolerance
- **Administration:** full CRUD for users (with role/session/active filters, pagination), rooms, beacons (with position X/Y for map placement); client-side validation mirroring backend rules
- **Settings:** AM/PM session windows, system config (staleness, timezone)
- **Reports:** date-range attendance summary (stat cards + per-learner table) + CSV download; on-demand rollup trigger
- Configurable backend URL (env var / Info.plist / compiled default)

### 5.6 Beacon Hardware (ESP32)

- iBeacon advertiser with a rotating `minor` value every 5 minutes (time-based)
- Pure BLE — no WiFi, no server communication; the phone is the relay
- Low power, always-on

### 5.7 Backend API

- Express/TypeScript on Node.js, MySQL 8 via mysql2
- 28+ REST endpoints across auth, learner, and admin surfaces
- Input validation via zod (strict schemas); parameterized SQL; rate limiting on auth/presence
- Request signature verification on presence; JWT verification on all protected routes
- Systemd-managed on Rocky Linux 9; one-command deploy script (`aegis-deploy`)
- 254 automated tests, TypeScript strict mode, ESLint

## 6. Data Model (key tables)

| Table | Purpose |
|-------|---------|
| USER | Accounts (learner/admin), credentials, device_public_key, session assignment |
| DEVICE | Registered beacons: name, identifier, room assignment, position |
| ROOM | Classrooms |
| PRESENCE_LOG | Raw presence pings (user, room, timestamp, position, battery) |
| ATTENDANCE_HISTORY | One row per learner per date: status (early/late/absent/leave) |
| REFRESH_TOKEN | Rotating tokens with reuse detection |
| SESSION_CONFIG | AM/PM start/late_after/end times |
| SYSTEM_CONFIG | Timezone, presence staleness threshold |

## 7. Security Model

- **Transport:** plain HTTP on internal LAN (acceptable for v1; HTTPS/Cloudflare planned for internet exposure)
- **Auth:** bcrypt-12 passwords; HS256 JWT (15 min access / 30 day refresh); token family revocation on reuse
- **Presence trust:** P-256 ECDSA device signatures; ±60s timestamp window; SHA-256 body binding
- **Input:** zod strict validation on every endpoint; max-length constraints; type coercion
- **SQL:** parameterized queries throughout; no string interpolation
- **Limitation:** iBeacon ads are unauthenticated — a modified client could spoof room presence. Device signing proves *which* phone, not *where* it physically is. Accepted for v1.

## 8. What's Not Built (Planned / Out of Scope)

| Item | Status |
|------|--------|
| CoreLocation beacon detection on the learner app | Planned — the main remaining work for end-to-end passive attendance |
| On-device trilateration for position_x/y | Planned |
| Cron job for nightly rollup | Trivial to add (script exists, just needs a crontab entry) |
| HTTPS / TLS | Planned when exposing to internet |
| Email-based password reset | Out of scope (admin resets passwords via CRUD) |
| Self-service registration | Out of scope |
| Multi-tenant / SaaS | Out of scope |

## 9. Success Criteria

A learner walks into a classroom with their iPhone in their pocket. Within seconds, the admin's Live Radar shows them in the room. At end of day, the rollup marks them `early` or `late`. The learner sees "Checked In" on their dashboard. No one pressed anything.

**Currently met except for the CoreLocation sensing trigger on the phone** — everything downstream (signing, ingestion, live status, rollup, admin visibility, learner dashboard) works end-to-end with synthetic or manually-triggered presence data.
