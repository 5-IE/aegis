# Aegis

**Passive, location-based attendance for a physical academy.** Learners walk
past classroom beacons and are recorded automatically; admins see live
occupancy and daily attendance without anyone tapping a "check in" button.

Aegis is an IoT + mobile + backend system built around Apple's CoreLocation /
iBeacon stack, with a hardware-backed device-signing layer so the backend can
trust that a presence report came from a registered physical device.

> **Status:** the backend, admin app, device-signing, and beacon firmware are
> built and (backend) tested. The learner app is a working attendance viewer
> with device registration and request signing wired; the passive
> beacon-detection → presence loop is the primary remaining piece. See the
> [Product Overview](docs/product-overview.md) for the full status and roadmap.

---

## The four subsystems

![System architecture](docs/diagrams/system-architecture.png)

| Directory | What it is | Stack |
|---|---|---|
| [`Aegis-Backend/`](Aegis-Backend) | REST API, auth, attendance logic, nightly rollup | Node.js 20 · TypeScript · Express · MySQL 8 |
| [`Aegis/`](Aegis) | Learner app — login, dashboard, history, device binding | SwiftUI · iOS |
| [`Aegis-Admin/`](Aegis-Admin) | Admin app — roster, rooms, beacons, users, live radar, config | SwiftUI · macOS |
| [`Aegis-Beacon/`](Aegis-Beacon) | Classroom beacon firmware (iBeacon advertiser) | ESP32 · Arduino/NimBLE |

## How it fits together

1. **ESP32 beacons** in each room broadcast an iBeacon advertisement (rotating
   minor value every 5 minutes to resist trivial cloning).
2. The **learner iPhone** detects nearby beacons and reports presence to the
   backend via a **signed** `POST /api/v1/presence` (device signature on top of
   the JWT — see [device signing](docs/device-signing-end-to-end.md)).
3. The **backend** stores raw pings, computes live status (checked-in / late /
   checked-out …), and a **nightly rollup** materializes one attendance row per
   learner per day (`early` / `late` / `absent` / `leave`).
4. The **admin macOS app** shows live occupancy ("radar"), the roster with
   today's status, and manages rooms, beacons, users, and session windows.

For the full data flow and the attendance state machine, see the
[Architecture](docs/architecture.md).

---

## Quickstart

### Backend

```bash
cd Aegis-Backend
cp .env.example .env          # set DB_* and a 32+ char JWT_SECRET
npm install
npm run migrate               # apply SQL migrations
npm run seed                  # create the seed admin (from .env)
npm run dev                   # http://localhost:3000  (GET /health → {status:'ok'})
```

Other scripts: `npm test` (Vitest), `npm run lint`, `npm run build`,
`npm run rollup` (attendance rollup), `npm run seed:dev`. See
[`Aegis-Backend`](Aegis-Backend) and [`docs/getting-started.md`](docs/getting-started.md).

### Apps (Xcode)

Open the learner (`Aegis/Aegis.xcodeproj`) or admin (`Aegis-Admin`) project in
Xcode and run. Point them at your backend via the `AEGIS_BASE_URL` environment
variable in the Run scheme, or the compiled-in default in
`AppEnvironment.swift`. The learner app's Secure Enclave signing path requires a
**real device** (the simulator uses a software-key fallback).

### Beacon

Flash [`Aegis-Beacon/ibeacon.ino`](Aegis-Beacon/ibeacon.ino) to an ESP32 with
the Arduino IDE + NimBLE library. Register the beacon's identifier and assign it
to a room from the admin app.

---

## Documentation

**Start here**
- [Product Overview](docs/product-overview.md) — what Aegis is, users, status, roadmap (the recap)
- [Product Requirements (PRD)](docs/product-requirements.md) — goals, requirements, scope
- [Architecture](docs/architecture.md) — subsystems, data model, flows, diagrams

**Reference**
- [Device Signing — end to end](docs/device-signing-end-to-end.md) · [protocol](docs/device-signing.md) · [iOS guide](docs/device-signing-ios.md)
- [API reference](docs/api-reference.html) · [Postman collection](docs/aegis.postman_collection.json) · [Integrating the API](docs/integrating-the-api.md)
- [Getting started](docs/getting-started.md) · [Deployment (Rocky 9)](docs/deployment-rocky9.md)
- [Signing test tool](docs/tools/README.md) — sign & test `POST /presence` without an iPhone
- [Tech report](docs/tech-report-v0.md) — decisions, what we tried, limitations hit

---

## Team

Azzahra Alfatrah · Felicia Sutanto · Hardy Tee · Steve Agustinus · William Antoline
