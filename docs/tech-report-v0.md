# Aegis — Tech Report


## Present your team

- Azzahra Alfatrah
- Felicia Sutanto
- Hardy Tee
- Steve Agustinus
- William Antoline

---

## Starting Assumption

*What we thought at kickoff, before writing any code:*

We think we'll end up using:
- **ESP32** boards flashed to advertise as **iBeacons** for classroom detection.
- **CoreLocation** on the iPhone learner app to detect those beacons in the background.
- **SwiftUI** for both the iPhone (learner) and macOS (admin) apps.
- **Node.js + TypeScript + Express** for the backend, with **MySQL** for storage.
- **OAuth2 with Authorization Code + PKCE** for auth, with a backend-served HTML login page opened by both native apps via ASWebAuthenticationSession.
- The iPhone would send the raw beacon identifier to the backend; the backend would resolve which room that maps to.

Because:
- The brief already named ESP32, CoreLocation, SwiftUI, and Node/TypeScript, so the platform decisions were mostly given.
- iBeacon is the natural CoreLocation companion for indoor proximity: anything else (WiFi triangulation, MultipeerConnectivity) would fight the framework rather than lean on it.
- OAuth2 PKCE is what every guide recommends for native mobile clients. It seemed like the obvious fit even though we hadn't thought hard about who the actual clients would be.

---

## The Exploration Log

*What we actually did, in order.*

**What we browsed, and what surprised us:**
- Apple's CoreLocation + iBeacon guides. Surprise: iBeacon detection can wake the app in the background, but the exact delivery timing is opaque and phone-battery-dependent.

**What we actually built or tested in code (not just read about):**
- Backend API: some endpoints across learner and admin surfaces, including authentication, presence ingestion, live radar (map + occupants), and admin config for session windows and staleness.
- Nightly rollup script (`npm run rollup`) that aggregates raw presence pings into `ATTENDANCE_HISTORY` with `early / late / absent / leave` status per learner per day.
- Migration runner and seed script; docker-compose file so any dev can spin up MySQL with one command.
- GitHub Actions CI running lint + type-check + tests on every PR touching the backend.

**What we discovered that we didn't expect:**
- The iBeacon protocol has **no** signing or secret in the broadcast. Anyone with the major/minor pair can spoof a beacon. This kills any "prove-you-were-here-with-hardware" story unless we buy custom hardware. Documented as a v1 limitation.
- Deleting PKCE: one HTML page, two tables, a cleanup cron, redirect handling on both apps, without giving up a single security property.

---

## What We Tried and Dropped

**We considered:**
[TODO]

**We dropped it because:**
[TODO]

---

## Real Limitations Hit

**Limitation 1: iBeacon broadcasts are unauthenticated.**

The iBeacon protocol (Apple's proximity beacon layer over Bluetooth LE) has no cryptographic identity in the advertisement, a beacon's major/minor pair is public, and anyone with a spare BLE radio can rebroadcast the same values. This means our backend cannot verify that a `/api/v1/presence` ping actually came from a phone that was physically near the classroom.

**How we worked around it:** We accepted this as a known v1 limitation. Attendance from the app is trusted at the same level as the authenticated user, if a learner shares their credentials, or sideloads a modified build that sends fake pings from home, the backend can't tell. Mitigations available if the problem gets real: a private BLE protocol on custom firmware with rotating tokens, or a physical checkpoint reader.

---

## The Revised Decision

**Final decision:**
- IoT: ESP32 flashed as iBeacon broadcasters, N per room.
- Learner app: iPhone / SwiftUI / CoreLocation.
- Admin app: macOS / SwiftUI.
- Backend: Node.js 20 + TypeScript + Express + MySQL 8. Plain JWT auth (HS256 access, opaque rotating refresh, bcrypt passwords). Deployed as a single Node process; MySQL either native or via Docker Compose.
- Attendance model: passive detection via iBeacon → CoreLocation region monitoring on the phone → periodic `POST /api/v1/presence` with `room_id`. First ping today = check-in, last ping = check-out. Nightly rollup materializes `ATTENDANCE_HISTORY` with per-learner status per day.


**What changed since Section 1, and why:**
[TODO]

---

## App Track Addendum

### About the Frameworks

*Does your use case genuinely need both frameworks working together, or could it work with just your main one?*

[TODO]

[[FILL IN: does the second framework actually earn its place, or would the product still work without it? Be honest — the template rewards honesty over completeness.]]

### About Accessibility and Localization

[TODO] *What did you decide to support, what did you decide not to, and why? "We didn't localize" is a fine answer if you can say why, "we didn't think about it" is not.*
[ ]

### About Privacy

*What data does the app actually need?*
- **Username + password** at login. Sent to the backend, verified against bcrypt hash, never stored in plaintext anywhere.
- **Location authorization (Always).** Required for background region monitoring, the whole point of the app is to detect when the learner walks past a classroom beacon without the app being open.
- **Bluetooth** (implicitly, via CoreLocation for iBeacon ranging).
- **Battery level** (optional, sent on each `POST /presence` for admin monitoring; not sensitive but explicitly declared).
- **No** contacts, photos, calendar, microphone, camera, health data, or motion data. Nothing else.

*What happens when the user says no to a permission?*
- **Location denied at first launch:** the app cannot do its job: attendance is passive by design. 
- **Location downgraded to "While Using":** background pings stop; attendance only records when the app is foregrounded. 
- **Bluetooth off:** CoreLocation region monitoring falls back to WiFi/cell coarse location, which is far too imprecise for classroom-level. Effectively the same as location-denied. 

---