# Aegis — Timestamp & Timezone Guide

How timestamps flow through the system, and what admins/developers need to know.

## The rule

**Everything is stored and transmitted in UTC. Display converts to local time.**

- Database `TIMESTAMP` columns → UTC
- API responses (`clocked_in_at`, `check_in_at`) → UTC ISO 8601 (e.g. `2026-07-09T00:30:00.000Z`)
- Admin app / learner app → parse as UTC, display in the device's local timezone
- Day boundaries (what counts as "today") → determined by the **system config timezone** setting

## System config timezone

Set in the admin app under **Settings → Timezone** (e.g. `Asia/Jakarta` for WIB, UTC+7).

This controls:
- Which calendar date a ping belongs to (a ping at 23:30 UTC on Jul 8 = 06:30 WIB Jul 9 → counts as Jul 9)
- Session window evaluation (AM session 07:00–12:00 means 07:00–12:00 **in this timezone**)
- The rollup's "yesterday" calculation (cron runs at 03:00 server time, rolls up the previous local day)

**If the academy moves or changes timezone, update this setting.** Historical data is unaffected (stored as UTC); only future computations change.

## Scenarios

### Learner arrives on time

- Academy timezone: `Asia/Jakarta` (UTC+7)
- AM session: starts 07:00, late_after 07:15
- Learner walks in at **07:10 WIB**
- Phone sends presence → stored as `00:10 UTC` in PRESENCE_LOG
- Rollup compares: first ping `00:10 UTC` vs late_after `07:15 WIB` converted to `00:15 UTC`
- 00:10 < 00:15 → **early** (on time)
- Learner's app shows: "Checked In" at "07:10 AM"
- Admin dashboard shows: "07:10" in the clocked-in column

### Learner arrives late

- Same setup, learner walks in at **07:20 WIB**
- Stored as `00:20 UTC`
- Compared against late_after `00:15 UTC`
- 00:20 > 00:15 → **late**
- Both apps show "07:20 AM", status "Running Late"

### Ping near midnight (day boundary)

- Learner pings at **23:50 WIB on Jul 8** (= 16:50 UTC Jul 8)
- Today's window in WIB: Jul 8 00:00 WIB → Jul 8 17:00 UTC to Jul 9 17:00 UTC
- 16:50 UTC Jul 8 < 17:00 UTC Jul 8 → falls in **Jul 7's window**, not Jul 8's
- Wait — that means the ping at 23:50 WIB Jul 8 is correctly in Jul 8's window (17:00 UTC Jul 7 to 17:00 UTC Jul 8)
- ✓ Assigned to the correct day

### Live Radar dot visibility

- Staleness setting: 5 minutes
- Learner pinged 3 minutes ago → dot is visible (last ping within 5 min)
- Learner pinged 7 minutes ago → dot disappears (stale)
- Learner moves to a different room → dot disappears from old room, appears in new one (query uses MAX timestamp per user, filtered to the specific room)

### Admin in a different timezone

- Academy: WIB (UTC+7), admin's Mac set to UTC+8 (WITA)
- Learner checks in at 07:30 WIB
- API returns `00:30 UTC`
- Admin's Mac converts to local: displays **08:30** (WITA)
- This is correct by clock but may confuse the admin — they see "08:30" while the session started at "07:00 WIB"
- **Recommendation:** admin devices should be set to the same timezone as the academy's system config

## Technical details (for developers)

### Database

- `PRESENCE_LOG.timestamp` — MySQL `TIMESTAMP` type, auto-set to `CURRENT_TIMESTAMP` on insert. Stored as UTC internally.
- `ATTENDANCE_HISTORY.date` — MySQL `DATE` type. A calendar date with no time/timezone component. Represents the local date the attendance belongs to.
- The mysql2 pool sets `timezone: '+00:00'` so MySQL converts TIMESTAMP values to UTC on the wire. Without this, MySQL sends values in the server's system timezone (WIB) which Node would misinterpret as UTC.

### Backend

- All time computations use `Date` objects (UTC internally in JS)
- Day boundaries computed via `combineLocalDateAndTime(date, '00:00:00', tz)` which converts local midnight → UTC
- `new Date()` in route handlers represents "now" in UTC — correct regardless of server OS timezone
- API serialization: `date.toISOString()` → always `...Z` suffix (UTC)

### Client apps

- iOS/macOS parse ISO 8601 strings as UTC `Date` objects
- `DateFormatter` with no explicit `.timeZone` displays in the **device's local timezone**
- This means the same UTC value displays as different clock times depending on the device's setting — this is correct and standard

### Device signature

- Uses Unix epoch seconds (`Date().timeIntervalSince1970` on iOS, `Date.now()/1000` on server)
- Epoch is UTC by definition — no timezone confusion possible
- ±60 second freshness window — only affected by clock drift, not timezone

## Troubleshooting

| Symptom | Likely cause |
|---------|-------------|
| Times displayed +7h or -7h off | Missing `timezone: '+00:00'` in pool.ts, or MySQL session timezone not UTC |
| Radar dots never disappear | Same timezone bug — staleness comparison broken |
| Learners marked late/absent when they were on time | Timezone shift makes their first ping appear 7h later than reality |
| Rollup produces wrong results for pings near midnight | Day boundary computed in wrong timezone |
| Admin sees different time than learner for same event | Devices in different timezones — expected behavior, not a bug |
| Presence signature "timestamp too old" | Device clock is >60s off from server clock (check NTP sync) |
