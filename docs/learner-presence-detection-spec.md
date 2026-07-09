# Learner App: Beacon Detection & Presence Reporting

**What this is:** The list of work needed to close the end-to-end passive attendance loop. Everything *downstream* of these tasks already works (the API, signing, ingestion, rollup, admin dashboard). This is the sensing trigger on the iPhone that makes it all automatic.

**Backend endpoint:** `POST /api/v1/presence` — already built, tested, deployed.
**Client signing:** already wired (`CryptoManager.shared.signRequest(...)` in `HttpService.swift`).
**API method:** already defined (`ApiService.sendPresence(roomId:positionX:positionY:batteryLevel:)` in `ApiService.swift:38-44`) — just never called.

---

## Tasks

### 1. Add CoreLocation + CoreBluetooth capabilities

- Add `CoreLocation.framework` and `CoreBluetooth.framework` to the Xcode target
- In Info.plist (or via build settings since the project uses `GENERATE_INFOPLIST_FILE`):
  - `NSLocationAlwaysAndWhenInUseUsageDescription` — "Aegis uses your location to record attendance when you enter a classroom."
  - `NSLocationWhenInUseUsageDescription` — same
  - `NSBluetoothAlwaysUsageDescription` — "Aegis detects classroom beacons via Bluetooth to record your attendance."
- Enable Background Modes: "Location updates" and "Uses Bluetooth LE accessories"
- The app MUST request `.authorizedAlways` (not just `.authorizedWhenInUse`) for background beacon detection to work

### 2. Create a `BeaconManager` service

Responsibilities:
- Request location authorization (`.authorizedAlways`) with proper fallback UI if denied/restricted
- Monitor for beacon regions using `CLLocationManager.startMonitoring(for: CLBeaconRegion)` — the region is defined by the beacon's UUID (hardcoded or fetched from the backend; currently all beacons use the same UUID defined in `Aegis-Beacon/ibeacon.ino:6`)
- On region entry (`didEnterRegion`), start ranging (`startRangingBeacons(satisfying:)`) to get individual beacon identifiers (major/minor)
- On region exit, stop ranging (saves battery)
- Map detected beacons to rooms (see task 3)
- Must handle all `CLAuthorizationStatus` states:
  - `.notDetermined` → request authorization
  - `.authorizedAlways` → proceed
  - `.authorizedWhenInUse` → show prompt explaining why Always is needed
  - `.denied` / `.restricted` → show a clear message directing to Settings; disable detection gracefully

### 3. Beacon → Room resolution

The app needs to know which beacon corresponds to which room. Two options (recommend A):

**A. Fetch from the backend at launch/periodically:**
- `GET /api/v1/beacons` (already exists, learner-accessible) returns `[{device_id, beacon_identifier, room_id, room_name, position_x, position_y}]` for all beacons assigned to a room
- The beacon's `beacon_identifier` should match the iBeacon's advertising identifier (UUID + major + minor combination — determine the mapping convention with the firmware team)
- Cache locally; refresh every few hours or on app foreground

**B. Hardcode a mapping table:** simpler but breaks when beacons are added/moved.

### 4. Trigger `sendPresence` on detection

When a beacon is ranged:
- Resolve the beacon to a `room_id` via the mapping from task 3
- Call `ApiService.sendPresence(roomId: room.id)` — the method already exists and the HTTP layer already signs the request
- **Throttle:** don't call on every single ranging callback. Backend ingestion is cheap, but sensible practice is once every 30–60 seconds per room (e.g. debounce: if we sent for this room in the last 30s, skip)
- On failure: swallow silently (don't show errors for background pings; the system tolerates gaps — rollup only needs one ping per day to mark "present")

### 5. Optional: position estimation (trilateration)

If multiple beacons are visible in the same room:
- Use RSSI + known beacon positions (`position_x`/`position_y` from the API) to estimate the learner's position
- Pass as `positionX`/`positionY` in the presence call — the admin's Live Radar will plot the dot
- Algorithm: non-linear least squares over the path-loss model, or weighted centroid for a simpler first pass
- **This is optional for v1.** Even without position, the system works — presence is binary (in room / not in room). Position just makes the radar map more useful.

### 6. Optional: battery level

- `UIDevice.current.batteryLevel` (0.0–1.0, multiply by 100 for percentage)
- Pass as `batteryLevel` in the presence call
- Useful for admins to monitor device health; purely informational

### 7. UI for authorization state

- If Bluetooth is off: show a banner/card on the Home screen ("Turn on Bluetooth for automatic attendance")
- If location is denied/restricted: show a banner ("Location access needed for attendance — tap to open Settings") with a button that opens `UIApplication.openSettingsURLString`
- If location is `.authorizedWhenInUse` (not Always): explain that "Always" is needed for background detection and prompt to upgrade
- These should be non-blocking — the app is still usable (manual data visible), just attendance won't be automatic

---

## What already works (don't rebuild)

- `ApiService.sendPresence(roomId:positionX:positionY:batteryLevel:)` — defined, correctly typed
- `HttpService.request(...)` — handles auth, 401 retry, and device signing (via `requiresSignature("/api/v1/presence")`)
- `CryptoManager.shared` — Secure Enclave key generation, storage, and ECDSA signing
- Backend: `POST /api/v1/presence` validates room exists, checks signature, stores the ping
- Backend: live status computation picks up new pings immediately
- Backend: rollup uses the pings to determine early/late/absent

## Beacon identifiers

The ESP32 firmware (`Aegis-Beacon/ibeacon.ino`) broadcasts:
- **UUID:** defined at compile time (line 6) — currently `FDA50693-A4E2-4FB1-AFCF-C25CF3B9E289` (a common test UUID; should be changed per deployment)
- **Major:** hardcoded (e.g. `1` — could represent a building or floor)
- **Minor:** rotates every 5 minutes based on uptime (`(millis() / ROTATION_INTERVAL) % 65535`)

The minor rotation means **you cannot use minor alone to identify a specific beacon** — it changes. The stable identifiers are UUID + Major. If each beacon has a unique Major (or Major+fixed-Minor-base if multiple beacons share a UUID), that's the mapping key. Coordinate with whoever configures the beacons on what `beacon_identifier` in the admin UI maps to in the BLE advertisement. This needs a decision before implementation.

## Testing without beacons

- Use a second iPhone or a Mac running a BLE advertiser app (e.g. "Beacon Simulator") to broadcast a known UUID/Major/Minor
- Or use the Xcode simulator's Location simulation (limited — doesn't support ranging)
- Best: use a real ESP32 beacon on the desk during development

---

## Summary

| # | Task | Effort estimate | Blocks |
|---|------|-----------------|--------|
| 1 | Add capabilities + entitlements + Info.plist keys | Small (30 min) | Everything below |
| 2 | BeaconManager (CLLocationManager + authorization handling) | Medium (half day) | 4, 7 |
| 3 | Beacon → room mapping (fetch from API + cache) | Small–Medium (2–3 hrs) | 4 |
| 4 | Trigger sendPresence on detection (with throttle) | Small (1–2 hrs) | — |
| 5 | Position estimation (trilateration) | Optional, Medium | — |
| 6 | Battery level | Trivial (15 min) | — |
| 7 | Authorization-state UI banners | Small (1–2 hrs) | — |

Total for the minimum viable detection (tasks 1–4 + 7): **~1 day of focused iOS work.**
