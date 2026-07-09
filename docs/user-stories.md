# Aegis — User Stories, Flows & Acceptance Criteria

Based on the shipped product as of 2026-07-09.

---

## Learner Stories

### US-L1: Login

**As a** learner, **I want to** log in with my username and password **so that** I can access my attendance dashboard.

**Flow:**
1. Open app → Login screen appears
2. Enter username + password → tap SIGN IN
3. Backend validates credentials → returns JWT + refresh token
4. App stores tokens and navigates to either Registration (if device not bound) or Home

**Acceptance Criteria:**
- [ ] Empty username/password shows inline validation message
- [ ] Wrong credentials shows "Username or password is incorrect"
- [ ] Successful login stores tokens in UserDefaults
- [ ] Subsequent launches skip login if tokens are valid (session restore)
- [ ] Login response's `require_device_registration` flag gates the next screen

---

### US-L2: Device Registration

**As a** learner, **I want to** register my physical device once **so that** my attendance reports are cryptographically tied to this iPhone.

**Flow:**
1. First login → app shows "Secure Device Binding" screen
2. Tap "Register Device" → app generates P-256 key pair in Secure Enclave
3. Public key uploaded to server (`POST /register-device`)
4. Success → tap "Continue" → navigate to Home
5. On subsequent launches, registration is skipped (persisted in UserDefaults)

**Acceptance Criteria:**
- [ ] Key generated in Secure Enclave (or software fallback on simulator)
- [ ] Public key stored on server as base64 X9.63 (65 bytes)
- [ ] Registration only happens once per device-account pair
- [ ] Reinstalling the app or switching devices requires re-registration
- [ ] Error message shown if registration fails (network error, server error)
- [ ] After registration, `require_device_registration` returns `false` on next login

---

### US-L3: View Today's Attendance Status

**As a** learner, **I want to** see whether I'm marked as checked in today **so that** I know my attendance was recorded.

**Flow:**
1. Home screen loads → calls `GET /api/v1/dashboard`
2. Backend computes today's status from presence logs + session config
3. App displays status card: "Checked In!", "Running Late", "Not Checked In", or "On Leave"

**Acceptance Criteria:**
- [ ] Status derived from `today_status` field (not hardcoded)
- [ ] Check-in time displayed as local time (e.g. "07:10 AM")
- [ ] Status updates on each app foreground (`.task` re-fetches)
- [ ] "Not Checked In" shown when no presence ping exists today
- [ ] "Running Late" shown when first ping is after `late_after` threshold

---

### US-L4: View Attendance History

**As a** learner, **I want to** see my past attendance records **so that** I can track my punctuality over time.

**Flow:**
1. Home shows last 5 records → tap "See All"
2. Full history view with month/year navigation
3. Each row: date, time range, status badge (On-time / Late / Leave)

**Acceptance Criteria:**
- [ ] History fetched from `GET /api/v1/histories`
- [ ] Month/year picker filters server-side
- [ ] Statuses correctly mapped: `early` → On-time, `late` → Late, `leave` → Leave
- [ ] Dates displayed in local format ("Mon, 7 Jul 2026")
- [ ] Empty state shown when no records exist for selected month

---

### US-L5: Automatic Presence Detection

**As a** learner, **I want** my iPhone to automatically detect classroom beacons and record my attendance **so that** I don't have to do anything manually.

**Flow:**
1. App running (foreground or background) with Location Always + Bluetooth permissions
2. iPhone detects iBeacon in range → resolves beacon to room via server mapping
3. App calls `POST /api/v1/presence` with room_id, signed with device key
4. Backend verifies signature + stores presence log
5. Admin radar updates; rollup will classify attendance at end of day

**Acceptance Criteria:**
- [ ] CoreLocation region monitoring active in background
- [ ] Beacon-to-room mapping fetched from `GET /api/v1/beacons` and cached
- [ ] Presence pings throttled to max 1 per 30 seconds per room
- [ ] Request signed with ECDSA (X-Timestamp + X-Signature headers)
- [ ] Backend rejects signatures older than ±60 seconds
- [ ] Pings silently swallowed on failure (no user-facing errors for background ops)
- [ ] Bluetooth/Location denied → informational banner on Home screen

---

### US-L6: Sign Out

**As a** learner, **I want to** sign out **so that** another person cannot access my attendance data on this device.

**Flow:**
1. Home screen → tap sign-out icon (top right)
2. App clears tokens from UserDefaults
3. Navigate back to Login screen

**Acceptance Criteria:**
- [ ] Tokens removed from UserDefaults
- [ ] Cached user/dashboard/history data cleared
- [ ] `isLoggedIn` flips to false → ContentView shows LoginView
- [ ] Failed token refresh also triggers automatic sign-out

---

## Admin Stories

### US-A1: Login

**As an** admin, **I want to** log in to the macOS dashboard **so that** I can monitor attendance.

**Flow:**
1. Launch app → Login screen (or auto-restore from Keychain)
2. Enter admin credentials → SIGN IN
3. Backend validates → returns JWT (must have `role: admin`)
4. Token stored in Keychain; navigate to Dashboard

**Acceptance Criteria:**
- [ ] Non-admin accounts rejected with "Please sign in with an admin account"
- [ ] Refresh token stored in macOS Keychain (not UserDefaults)
- [ ] Session survives app restart (restoreSession via stored refresh token)
- [ ] Proactive token refresh at 60s before expiry (no 401 storms)
- [ ] Coalesced refresh: concurrent 401s share one refresh call
- [ ] Network failure during restore shows "server unreachable" notice (doesn't destroy token)
- [ ] Expired session shows "session expired" on login screen

---

### US-A2: View Dashboard

**As an** admin, **I want to** see today's attendance summary at a glance **so that** I know how many learners are present, late, or absent.

**Flow:**
1. Dashboard tab → loads absence summary + attendance overview
2. Summary cards: On Time count, Late Clock-in count, Absent count, No Clock-in count
3. Table: learner name, session, clock-in time, clock-out time, status

**Acceptance Criteria:**
- [ ] Summary cards show present_summary (on_time, late_clock_in) and absent_summary (absent, no_clock_in)
- [ ] Table is paginated (100 per page, footer shows page info)
- [ ] Name search filters server-side (applied on Enter or clear)
- [ ] Session filter (All/AM/PM) applies on picker change
- [ ] Clock-in/out times displayed in admin's local timezone
- [ ] Status shows: "Checked In", "Running Late", "Not Checked In", "Checked Out", "Not Checked Out", "Off"

---

### US-A3: Monitor Live Radar

**As an** admin, **I want to** see which learners are currently in each room in real time **so that** I know classroom occupancy.

**Flow:**
1. Live Radar tab → loads room list
2. Select a room → shows radar map + occupants table + metrics
3. Polls every 5 seconds for updates
4. Green dots = learners (positioned by their last ping's X/Y)
5. Blue markers = beacons (positioned by admin-configured X/Y)

**Acceptance Criteria:**
- [ ] Room tabs show all rooms from the system
- [ ] Radar map plots occupant dots inside the room rectangle (normalized 0-1 coordinates)
- [ ] Beacon markers show at their configured positions (only if both X/Y are set)
- [ ] Dots appear within 5s of a presence ping being recorded
- [ ] Dots disappear after the staleness timeout (default 5 min, configurable in Settings)
- [ ] Switching rooms cancels in-flight requests (no stale-room data displayed)
- [ ] Transient poll errors tolerated for up to 3 consecutive failures before showing error
- [ ] Occupants table shows: learner name, session, duration, today's status
- [ ] People-in-room metric is accurate; temperature/humidity labeled "Sample data"

---

### US-A4: Manage Users

**As an** admin, **I want to** create, edit, and deactivate learner/admin accounts **so that** I control who has access.

**Flow:**
1. Administration → Users tab
2. List with pagination, search, role/session/inactive filters
3. Create: username, password, email, role, session (if learner), optional first/last name
4. Edit: all fields except username; password via separate reset button
5. Deactivate: soft-delete with confirmation (no self-delete allowed)
6. Reactivate: restore access with confirmation

**Acceptance Criteria:**
- [ ] List is server-paginated (20 per page)
- [ ] Search by name (server-side), role filter, session filter, include-inactive toggle
- [ ] Create validates: username 1-50, password 1-72, valid email ≤100, role required
- [ ] Edit validates same rules (minus password)
- [ ] Password reset: separate form, 1-72 chars
- [ ] Deactivate: confirmation dialog, backend returns 204, list refreshes
- [ ] Cannot deactivate yourself (button disabled)
- [ ] Reactivate: confirmation dialog, backend returns 204
- [ ] Save errors show inside the form sheet (not behind it)
- [ ] Page clamps after deleting the last item on a page

---

### US-A5: Manage Rooms

**As an** admin, **I want to** create, rename, and delete rooms **so that** the system reflects the physical classroom layout.

**Flow:**
1. Administration → Rooms tab
2. List shows all rooms with beacon count per room
3. Create/Edit: room name (1-100 chars)
4. Delete: confirmation, blocked if room has presence logs

**Acceptance Criteria:**
- [ ] Room list shows beacon count and assignment status per room
- [ ] Create/edit validates name 1-100 characters
- [ ] Delete shows confirmation; backend returns 409 if presence logs exist (shown as error)
- [ ] After create/edit/delete, list refreshes automatically

---

### US-A6: Manage Beacons

**As an** admin, **I want to** register beacons and assign them to rooms with positions **so that** the Live Radar shows accurate beacon markers.

**Flow:**
1. Administration → Beacons tab
2. List with assignment/room filters, pagination
3. Create: name, identifier, optional room assignment, optional position X/Y
4. Edit: same fields; clearing room = unassign
5. Delete: with confirmation

**Acceptance Criteria:**
- [ ] List is server-paginated (20 per page)
- [ ] Assignment filter: All / Assigned / Unassigned
- [ ] Room filter: filter beacons by room
- [ ] Position X/Y validated 0-1 (or empty for "no position")
- [ ] Unassigning a beacon sends explicit null for room_id (not omitted)
- [ ] Beacon markers appear on Live Radar only when both positions are set
- [ ] Create/edit validates: name 1-100, identifier 1-100

---

### US-A7: Generate Attendance Reports

**As an** admin, **I want to** generate attendance reports for a date range **so that** I can review and share attendance data.

**Flow:**
1. Reports tab → Attendance Report panel
2. Pick from/to dates (max 92 days) + optional session filter
3. Click Generate → summary stats + per-learner table displayed
4. Click Download CSV → NSSavePanel → file saved locally

**Acceptance Criteria:**
- [ ] Date range validated: from ≤ to, range ≤ 92 days
- [ ] Summary shows: attendance rate (%), learner count, total late, total absent
- [ ] Per-learner table: name, session, present days, late days, absent days, individual rate
- [ ] Attendance rate = present / (present + absent); leave excluded from denominator
- [ ] CSV has columns: date, user_id, name, session, status, clocked_in_at, clocked_out_at
- [ ] CSV filename includes the date range
- [ ] Empty date range shows "No attendance data in the selected range"
- [ ] Error response shows inline error banner

---

### US-A8: Run Manual Rollup

**As an** admin, **I want to** manually trigger the attendance rollup **so that** I can backfill or re-process a specific day.

**Flow:**
1. Reports tab → Rollup panel (below the attendance report)
2. Optionally toggle "Specific Date" and pick a date (default: yesterday)
3. Optionally enter a User ID (default: all learners)
4. Click "Run Rollup" → shows processed + leave-skipped counts

**Acceptance Criteria:**
- [ ] Empty date = backend defaults to yesterday in system timezone
- [ ] Date formatted as YYYY-MM-DD (DatePicker)
- [ ] User ID validated as positive integer (or empty for all)
- [ ] Response shows: processed count, leave-skipped count
- [ ] Leave-status records are not overwritten (skipped)
- [ ] Rollup is idempotent (running twice for the same day updates, doesn't duplicate)

---

### US-A9: Configure Session Windows

**As an** admin, **I want to** set the AM/PM session start times and late thresholds **so that** attendance classification is accurate for our schedule.

**Flow:**
1. Settings tab → Session Config panel
2. AM and PM sections: start_time, late_after, end_time (HH:MM:SS format)
3. Click Save → saves AM config, PM config, and system config in sequence

**Acceptance Criteria:**
- [ ] Times displayed/edited in HH:MM:SS format
- [ ] Backend validates: start < late_after < end
- [ ] Save reports per-PUT outcomes: "AM saved, PM saved, System saved" or individual failures
- [ ] System config includes: presence_staleness_minutes (1-60) and timezone (IANA string)
- [ ] Changes take effect immediately for new status computations (no restart needed)

---

### US-A10: Dark Mode

**As an** admin/learner, **I want** the app to respect my system appearance setting **so that** I can use it comfortably in low-light environments.

**Flow:**
1. System Settings → Appearance → Dark
2. App adapts: dark backgrounds, light text, brand colors preserved

**Acceptance Criteria:**
- [ ] Both apps (macOS admin + iOS learner) respond to system appearance toggle
- [ ] All text remains readable (no black-on-dark or white-on-light)
- [ ] Brand colors (teal buttons, green/yellow/red status) stay fixed in both modes
- [ ] Cards/panels use elevated dark surfaces, not flat black
- [ ] Admin gradient becomes subtle/muted in dark mode
- [ ] No additional UI toggle needed — follows system setting automatically

---

## System Stories

### US-S1: Nightly Attendance Rollup

**As** the system, **I want to** run the attendance rollup every night at 3:00 AM **so that** daily attendance records are available for reporting the next morning.

**Flow:**
1. Cron fires at 03:00 server time (`/etc/cron.d/aegis-rollup`)
2. Script runs: for each learner, find first ping of yesterday → classify early/late/absent
3. Results written to ATTENDANCE_HISTORY table
4. Log written to `/var/log/aegis-rollup.log`

**Acceptance Criteria:**
- [ ] Runs automatically daily at 03:00 without manual intervention
- [ ] Defaults to "yesterday" in the configured system timezone
- [ ] Classification: first ping ≤ late_after → early; first ping > late_after → late; no ping → absent
- [ ] Existing `leave` records are not overwritten (skipped)
- [ ] Idempotent: re-running for the same date updates (upsert), doesn't create duplicates
- [ ] Log output includes processed count and skipped-leave count
- [ ] Log rotated weekly (4 weeks retained)

---

### US-S2: Device Signature Verification

**As** the system, **I want to** verify that every presence report comes from the registered physical device **so that** attendance cannot be faked from another device.

**Flow:**
1. Learner app signs `POST /presence` with its Secure Enclave private key
2. Signature covers: METHOD + PATH + TIMESTAMP + SHA256(body)
3. Backend retrieves stored public key for the user
4. Verifies ECDSA signature; rejects if invalid or timestamp outside ±60s

**Acceptance Criteria:**
- [ ] Missing X-Timestamp or X-Signature → 400 "Missing headers"
- [ ] Timestamp > 60s old or in the future → 400 "Timestamp too old"
- [ ] No device registered for user → 403 "No device registered"
- [ ] Invalid/wrong signature → 403 "Invalid device signature"
- [ ] Valid signature → request proceeds to presence recording
- [ ] Signature is over exact request body bytes (no re-serialization drift)

---

### US-S3: Token Security

**As** the system, **I want to** detect and revoke token reuse **so that** stolen refresh tokens cannot be exploited.

**Flow:**
1. Client sends refresh token → backend rotates: issues new access + refresh, revokes old
2. If a revoked token is presented again → entire token family revoked for that user
3. All sessions for that user are invalidated

**Acceptance Criteria:**
- [ ] Each refresh rotates the token (old one revoked)
- [ ] Presenting a revoked token → all tokens for that user revoked ("reuse detection")
- [ ] Access token TTL: 15 minutes; refresh token TTL: 30 days
- [ ] Rate limit on auth endpoints: 60 attempts per 15 min per IP:username
- [ ] Admin app coalesces concurrent refresh calls (single shared task)

---

## Deployment Stories

### US-D1: One-Command Deploy

**As a** developer, **I want to** deploy backend changes with a single command **so that** I can ship quickly without manual SSH steps.

**Flow:**
1. Push to main
2. Run: `ssh -p 484 freuch@10.64.58.125 sudo -n aegis-deploy`
3. Script: fetch → ff-merge → npm ci (if lockfile changed) → migrate → restart → health check

**Acceptance Criteria:**
- [ ] Single command, no password prompts (SSH key + passwordless sudo)
- [ ] Dependencies installed only when package-lock.json changes (detected via git diff)
- [ ] Migrations run automatically (idempotent, skip already-applied)
- [ ] Service restarted and health check verified before reporting success
- [ ] Failure at any step aborts with a clear error message
- [ ] In-memory rate limiter resets on restart (known side effect, documented)
- [ ] Sessions survive restart (JWT + refresh tokens are in the database)

---

### US-D2: Error Monitoring

**As a** developer, **I want** unhandled errors to appear in Sentry **so that** I'm alerted to production issues without checking logs manually.

**Flow:**
1. An unhandled exception occurs in any of the three apps
2. Sentry SDK captures it with context (stack trace, breadcrumbs, environment)
3. Event appears in the Sentry dashboard within seconds

**Acceptance Criteria:**
- [ ] Backend: `@sentry/node` initialized, errors forwarded via `setupExpressErrorHandler`
- [ ] Admin app: Sentry Cocoa SDK initialized in `App.init()`; sessions tracked
- [ ] Learner app: Sentry Cocoa SDK initialized (when SPM package added); sessions tracked
- [ ] Each app reports to its own Sentry project (separate DSNs)
- [ ] Environment tag distinguishes production vs development
- [ ] `attachScreenshot` enabled on iOS only (not macOS)
