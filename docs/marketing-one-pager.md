# Aegis — Passive Attendance, Zero Effort

## The pitch

**Walk in. Get marked present. That's it.**

Aegis is an IoT attendance system that records when learners enter a classroom — automatically, silently, and trustworthily. No QR codes. No taps. No roll calls. Just walk past the door with your phone in your pocket.

## How it works

1. **Beacons in every room.** Tiny ESP32 boards broadcast a Bluetooth signal. Learners don't interact with them — they just exist.

2. **The learner's iPhone listens.** When it detects a classroom beacon, it reports "I'm here" to the server — signed with the phone's hardware key so it can't be faked from another device.

3. **The admin sees everything.** A macOS dashboard shows who's in which room right now, who arrived on time, who's late, who's absent — live and historical.

## What makes it different

| Traditional | Aegis |
|-------------|-------|
| Manual roll call — slow, gameable | Fully automatic — no learner action |
| QR/NFC tap — requires deliberate action, can be proxied | Passive detection — phone in pocket is enough |
| Badge swipe — expensive hardware per door | Low-cost ESP32 beacons, commodity iPhones |
| Trust the token | Trust the hardware — device-signed requests are cryptographically bound to the physical phone |

## For learners

- **Zero friction.** Attendance is invisible. Just carry your phone.
- **See your status.** Dashboard shows today's check-in, total attendance, and full history.
- **One-time setup.** Register your device once (30 seconds), then never think about it again.

## For admins

- **Live Radar.** See every occupied room in real time — who's there, when they arrived, plotted on a map.
- **Daily roster.** Today's attendance table with on-time / late / absent at a glance.
- **Reports.** Pull attendance data for any date range — summary stats or downloadable CSV for Excel.
- **Full control.** Manage rooms, beacons, users, session windows, all from a native macOS app.
- **Trustworthy data.** Presence reports are hardware-signed — you know which specific device reported, not just which token.

## The numbers

| Metric | Value |
|--------|-------|
| Learner effort to check in | 0 taps |
| Time to deploy a new room | ~2 minutes (plug in a beacon, assign it in the app) |
| Beacon cost | ~$5 per ESP32 board |
| Detection latency | Seconds (BLE range + 5s polling) |
| Backend API coverage | 28 endpoints, 254 automated tests |

## Tech stack

- **Beacons:** ESP32 (iBeacon mode, rotating minor for anti-replay)
- **Learner app:** iOS / SwiftUI (Secure Enclave for device key)
- **Admin app:** macOS / SwiftUI (native, fast, built for all-day use)
- **Backend:** Node.js / TypeScript / Express / MySQL 8
- **Security:** JWT auth + P-256 ECDSA device signatures + bcrypt + rate limiting

## Current state

The backend, admin app, learner app UI, device signing, and beacon firmware are all built and deployed. The one remaining piece — CoreLocation beacon detection on the iPhone — closes the loop from "everything works if you trigger it" to "everything works by walking past."

---

*Aegis: attendance that happens without anyone noticing.*
