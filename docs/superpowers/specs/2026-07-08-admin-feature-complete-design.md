# Aegis-Admin: Stability + Feature-Complete Design

**Date:** 2026-07-08 · **Base:** main @ `85cf116` · **Scope decided with:** William
**Goal:** Everything in the project brief and README implemented, on a stable auth foundation. Backend endpoints included where a feature needs them.

Companion one-pager: [`../../admin-todos.md`](../../admin-todos.md)

## Decisions (from brainstorming, 2026-07-08)

- Scope: Aegis-Admin (+ backend endpoints its features require). Learner app / ESP32 untouched.
- "Done" = feature-complete vs the brief, built in stability-first order (Approach A).
- Forgot-password and sign-up: **dropped**. Admin accounts are created and passwords reset by other admins in the Administration screen. Remove the dead login-screen links.
- Reports: **CSV export + in-app summary stats** over a date range.
- Room temperature/humidity: keep the stubbed cards, **label as sample data**.
- Base URL: reuse the `AppEnvironment` resolution pattern from PR #32 (env var → Info.plist → compiled default); no in-app settings UI.

## Phase 1 — Auth layer hardening

All changes in `SessionStore.swift`; no UI changes. The three bugs share one root design flaw: refresh is a side effect of individual requests instead of a managed, single-owner concern.

### 1.1 Coalesced refresh

`SessionStore` (a `@MainActor` class) gains:

```swift
private var refreshTask: Task<AuthResponse, Error>?
```

`refreshAndRetry` becomes: if `refreshTask` exists, `try await` its value; otherwise create the task (capturing the current refresh token), store it, and clear it in a `defer` when it completes. All concurrent 401 handlers therefore await one network refresh. Because the store is main-actor-isolated, check-and-set of `refreshTask` is race-free — the await happens only after the task is registered.

On success the task updates `accessToken`/`refreshToken` and persists the rotated refresh token to the Keychain **inside the task**, before any awaiter resumes, so no awaiter can observe the stale token.

### 1.2 Proactive refresh

`AuthResponse.expiresIn` is already decoded and currently unused. Store `tokenExpiryDate = now + expiresIn` on login/refresh. In `authorized`, before running the operation: if `now > tokenExpiryDate - 60s`, await the coalesced refresh first. The reactive 401 path stays as a fallback (clock skew, server-side revocation), but in normal operation the 3-parallel-requests-all-401 storm never happens.

### 1.3 Error-discriminating restore and sign-out on refresh death

- `restoreSession`: catch clause distinguishes `AegisAPIError` cases. `invalid_grant` / 401 → `signOutLocally()` (token truly dead). Network/timeout/5xx → keep the Keychain token, set `state = .signedOut(reason: .serverUnreachable)` without purging; next launch or a retry can still restore.
- `refreshAndRetry` failure with `invalid_grant` → call `signOutLocally()` and set `state = .signedOut(reason: .sessionExpired)`. `SignedOutReason` is a new enum rendered on the login screen as an informational banner ("Your session expired — please sign in again."), styled as info, not error.
- View-model poll loops already handle thrown errors; once state flips to `.signedOut`, `ContentView` swaps to `LoginView` (existing behavior) and polls stop via `.onDisappear`.

**Testing:** unit-test the coalescing with a mock API client that counts refresh calls under 3 concurrent `authorized` calls returning 401 (expect exactly 1). Manual: leave app on Live Radar > 15 min against production; kill backend, relaunch app, confirm token survives; restart backend, confirm restore works.

## Phase 2 — Correctness fixes in existing screens

### 2.1 Administration state separation (bug 5)

Split `AdministrationViewModel`'s beacon state into two independent slices:

- `beaconListState` — the Beacons tab: filtered, paginated, owned solely by that tab.
- `roomBeaconSummary: [Int: (count: Int, active: Bool)]` — per-room aggregates for the Rooms tab.

`fetchRoomsAndBeaconSummary` writes only `roomBeaconSummary`. For correctness past 100 beacons (bug 11): loop `page` until `list.count` accumulates to `total` (per_page 100, so 2–3 requests worst case at this project's scale). Tab switches always refetch that tab's slice (cheap; also fixes stuck-failed-state bug 10, together with a Retry button on the error view).

### 2.2 Sheet-local errors and explicit outcome type (bugs 4, 6)

- Save/delete paths return a new `ActionOutcome` enum — `.success(message)` / `.failure(message)` — instead of a bare string; `AdminPaginationFooter` colors by case, killing the keyword heuristic.
- Each form sheet gains an inline error area; on failure the sheet stays open with the message inside it, and the background table is NOT flipped to `.failed` (the list data is still valid).

### 2.3 Race guards (bugs 9, 16)

Standard pattern in `LiveRadarViewModel` and `AdministrationViewModel`: keep the load `Task` handle, cancel the prior one on new intent (room switch, filter change, page change), and guard after each await (`guard roomID == selectedRoomID`, or `try Task.checkCancellation()`) before writing state. Poll writes also guard on current selection.

### 2.4 Pagination and filter behavior (bugs 8, 13, 15)

- Dashboard overview: add the same `AdminPaginationFooter` used in Administration, driven by the `total`/`page` fields the API already returns and the client already decodes. Default per_page stays 100 — the footer just makes >100 reachable.
- Page clamping: after any delete/refetch, if `page > ceil(total/perPage)` refetch at the last valid page.
- Dashboard filters: session picker applies via `.onChange` (drop the Apply button); clearing the search field reloads (`.onChange` on the binding detecting transition to empty). Search keeps `onSubmit` for typed queries.

### 2.5 Client-side validation (bug 14)

A small `FormValidators` helper mirroring the backend zod rules (single source list documented alongside): email regex + ≤100, password 1–72, username ≤50, names ≤50, room/beacon name & identifier ≤100, user search ≤100, rollup date `^\d{4}-\d{2}-\d{2}$` (use a `DatePicker` and format programmatically instead of free text). Validation errors show inline in the form before any network call; backend remains the authority.

### 2.6 Cosmetics (bug 17 + label decision)

- Temperature/humidity cards get a "Sample data" caption until real ingestion exists.
- Occupants "Last Update" column: remove it (backend provides no such field; showing fabricated "Now" is worse than absence).
- Stable row identity: `AttendanceOverviewRow.id` derived from `(name, session)`; `BeaconMarkerData` id from beacon identifier.
- Settings save: keep 3 PUTs but report per-request outcomes ("AM saved, PM failed: …") instead of one generic failure.
- Login: `disabledFeatureMessage` disappears with the dropped links (Phase 3.3); stale `authError` cleared whenever a new sign-in attempt starts, including validation-only failures.

## Phase 3 — Features

### 3.1 Base URL configuration (bug 7)

Copy the learner app's `AppEnvironment.swift` (from PR #32, `Aegis/Aegis/AppConfig/`) into Aegis-Admin, adjusted:

- Resolution: `AEGIS_BASE_URL` env var → `AEGIS_BASE_URL` Info.plist key → compiled default `http://10.64.58.125:3000` (production).
- `AegisAPIClient.init` default becomes `AppEnvironment.current.baseURL`; force-unwrap replaced with a `preconditionFailure` carrying the offending string.
- Xcode scheme gets `AEGIS_BASE_URL=http://localhost:3000` as a commented-out env var for local dev.

### 3.2 Reports — CSV + summary stats (backend + app)

**Backend** — new route file `Aegis-Backend/src/routes/admin/reports.ts`, mounted at `/api/v1/admin/reports`, admin-gated like siblings:

`GET /attendance?from=YYYY-MM-DD&to=YYYY-MM-DD[&session=AM|PM][&user_id=N][&format=csv]`

- Validation (zod, `.strict()` query): `from`/`to` required, date regex, `from ≤ to`, range ≤ 92 days (`invalid_request` otherwise); optional session enum and positive-int user_id.
- JSON response:

```json
{
  "range": {"from": "...", "to": "...", "days_with_sessions": 12},
  "summary": {"learners": 24, "attendance_rate": 0.87, "total_late": 9, "total_absent": 14},
  "per_learner": [{"user_id": 3, "name": "…", "session": "AM",
                   "present": 11, "late": 2, "absent": 1, "attendance_rate": 0.92}],
  "records": [{"date": "…", "user_id": 3, "name": "…", "session": "AM",
               "status": "…", "clocked_in_at": "…", "clocked_out_at": "…"}]
}
```

- Data source: the existing attendance/rollup tables that power `/admin/overview` (`overviewService` queries are the template). Aggregation in SQL, not JS. Status vocabulary reuses `statusService`'s canonical strings.
- `format=csv`: same query, streamed as `text/csv` with `Content-Disposition: attachment; filename=aegis-attendance-<from>-<to>.csv`. One row per `records` entry; header row fixed; RFC-4180 quoting.
- Add both variants to the Postman collection.

**App** — replace the current rollup-only panel with a Reports screen:

- Controls: two `DatePicker`s (default: last 7 days), optional session picker, Generate button.
- Results: summary stat cards (attendance rate, late, absent) + per-learner table, reusing the existing table components.
- "Download CSV": `URLSession` download with the bearer token via `SessionStore.authorized`, then `NSSavePanel` (the sandbox's user-selected read/write covers this; add the `com.apple.security.files.user-selected.read-write` entitlement — currently read-only).
- The existing rollup trigger moves into this screen as a secondary action, with its free-text date replaced by a `DatePicker`.
- New API client methods follow the existing CodingKeys/snake_case conventions; errors decode via the shared `BackendErrorResponse`.

### 3.3 Login screen cleanup

Remove the "Forgot password?" and "Sign up" buttons and `disabledFeatureMessage` plumbing from `LoginView`/`LoginViewModel`. README "Not implemented yet" list updated: those two entries are removed as won't-do (with the rationale), reports entry flips to implemented when 3.2 lands.

### 3.4 Reactivate confirmation

Same confirmation-alert pattern as delete, with reactivate-specific copy.

## Delivery order and verification

| Step | Contents | Verification gate |
|---|---|---|
| PR 1 | Phase 1 (SessionStore) | Coalescing unit test; >15 min Live Radar soak against production; offline-launch restore test |
| PR 2 | Phase 2 (screen fixes) | Backend integration manual pass per screen; regression: create/edit/delete each entity with duplicate-name failure visible in sheet |
| PR 3 | 3.1 + 3.3 + 3.4 (small app-only items) | App reaches production with no code edit; login screen has no dead links |
| PR 4 | 3.2 backend (reports endpoint + tests + Postman) | Endpoint tests incl. validation edges; CSV opens in Numbers/Excel |
| PR 5 | 3.2 app (Reports screen) | End-to-end: generate report + download CSV against production |

Each PR is independently deployable; backend PRs deploy via `aegis-deploy`.

## Out of scope

Email/SMTP (password reset), self-service registration, PDF reports, real temperature/humidity ingestion, learner app, ESP32 firmware, HTTPS.
