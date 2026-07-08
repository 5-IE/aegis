# Aegis-Admin — Outstanding Work (one-pager)

Status as of 2026-07-08, main @ `85cf116`. Findings verified by code review against the live backend contract; file references are to current main. Design details in [`superpowers/specs/2026-07-08-admin-feature-complete-design.md`](superpowers/specs/2026-07-08-admin-feature-complete-design.md).

## P0 — Session-breaking bugs (auth layer)

| # | Item | Where |
|---|------|-------|
| 1 | Refresh-token stampede: concurrent 401s each refresh with the same token; backend reuse-detection revokes the whole family → session self-destructs after ~15 min on Live Radar. Needs a single shared refresh task + proactive refresh from `expires_in`. | `SessionStore.swift:328-337` |
| 2 | `restoreSession` deletes the Keychain refresh token on ANY error, including the backend simply being unreachable at launch. Purge only on `invalid_grant`. | `SessionStore.swift:114-116` |
| 3 | No recovery after refresh failure: app stays "signed in" showing error banners every 5 s forever. Should transition to the login screen with a "session expired" notice. | `SessionStore.swift:144-156` |

## P1 — Wrong or invisible data in existing screens

| # | Item | Where |
|---|------|-------|
| 4 | Save errors render behind the modal form sheet; failures (e.g. duplicate username) look like silent no-ops. | `AdministrationViews.swift:175-187` |
| 5 | Rooms and Beacons tabs share one `beacons` array and corrupt each other's filters/pagination/per-room counts. | `AdminViewModels.swift:504-521` |
| 6 | Success/error coloring guesses by keyword: "Username already exists" renders green. | `AdministrationViews.swift:481-483` |
| 7 | Base URL hardcoded to `http://127.0.0.1:3001` — app cannot reach production without a code edit. Port the learner app's `AppEnvironment` pattern (PR #32). | `AegisAPIClient.swift:576` |
| 8 | Dashboard overview capped at page 1 / 100 rows with no pagination UI — learner #101 is silently invisible. | `AegisAPIClient.swift:367-370` |
| 9 | Room-switch race: stale in-flight responses overwrite the newly selected room's radar/occupants. | `AdminViewModels.swift:120-130,154-161` |

## P2 — Correctness polish

| # | Item |
|---|------|
| 10 | Failed Rooms/Beacons tab loads have no retry path (stuck until app restart). |
| 11 | Per-room beacon counts fetched with hard `per_page=100` — wrong past 100 beacons. |
| 12 | Beacon text search filters only the loaded page; totals line lies about what's shown. |
| 13 | Deleting the last row of a page leaves an out-of-range page (empty table, "Showing 21-20 of 20"). |
| 14 | Client validation gaps vs backend zod: email format, password ≤ 72, field max-lengths, rollup date `YYYY-MM-DD` — all currently surface as a generic "malformed request". |
| 15 | Dashboard session filter needs a hidden second "Apply" click; clearing search doesn't reload. |
| 16 | Fetch races on rapid filter/page clicks (no cancellation); stale login error masks newer validation messages. |
| 17 | Cosmetics: occupants "Last Update" hardcoded to "Now"; row `id = UUID()` regenerated every poll; settings save is 3 non-atomic PUTs; temperature/humidity are backend stubs — label as sample data. |

## P3 — Features to reach the brief

| # | Item | Backend work |
|---|------|--------------|
| 18 | **Reports**: CSV attendance export + in-app summary stats (attendance rate, late/absent counts per learner, date range). | New `GET /api/v1/admin/reports/attendance` (JSON + `format=csv`) |
| 19 | Login screen cleanup: remove dead "Forgot password?" / "Sign up" links (admin accounts are managed via Administration; decision 2026-07-08). | none |
| 20 | Reactivate-user confirmation dialog (delete has one, reactivate doesn't). | none |

## Explicitly out of scope

Email/SMTP infrastructure, PDF reports, real temperature/humidity ingestion from the ESP32, learner app changes, HTTPS termination.
