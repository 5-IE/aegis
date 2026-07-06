# Getting Started - Aegis Admin macOS

Aegis Admin is the macOS dashboard for monitoring learner attendance, live room presence, and attendance settings. It is a native SwiftUI app that talks to the Aegis backend at `http://localhost:3000` by default.

If you get stuck, jump to [Troubleshooting](#troubleshooting).

---

## Current scope

Implemented in the macOS app:

- Admin login
- Dashboard summary cards
- Daily attendance overview table
- Live Radar room tabs, map, occupants, and room metrics
- Attendance/session settings
- Sidebar placeholders for Administration and Reports

Not implemented yet because backend APIs do not exist yet:

- Learner CRUD
- Room CRUD
- Beacon CRUD
- Report export/download
- Forgot password
- Sign up

---

## Prerequisites

Install these first:

- **macOS with Xcode.** Open the project with Xcode, not only Command Line Tools.
- **A running Aegis backend.** The app expects `http://localhost:3000`.
- **Docker Desktop** if you want the recommended local MySQL setup.
- **Node.js 20 or newer** for running the backend locally.

The backend docs are in the root `docs/` folder:

- `docs/getting-started.md`
- `docs/integrating-the-api.md`
- `docs/API.md`

There is currently no equivalent Beacon documentation in `Aegis-Beacon`; that folder only has a `.gitignore` at the time this guide was written.

---

## Step 1 - Start the backend locally

From the repo root:

```bash
docker compose up -d
```

Then configure and start the backend:

```bash
cd Aegis-Backend
npm install
cp .env.example .env
```

If using Docker MySQL, make sure `.env` uses:

```env
DB_HOST=localhost
DB_PORT=3306
DB_USER=aegis
DB_PASSWORD=aegispassword
DB_NAME=AEGIS
```

Generate a JWT secret:

```bash
node -e "console.log(require('crypto').randomBytes(48).toString('base64'))"
```

Paste it into `.env` as:

```env
JWT_SECRET=<generated value>
```

Then run:

```bash
npm run migrate
npm run seed
npm run dev
```

Verify the backend:

```bash
curl http://localhost:3000/health
```

Expected response:

```json
{"status":"ok"}
```

The seeded admin login is controlled by `.env`. With the example values:

```text
username: admin
password: changeme
```

---

## Step 2 - Open the macOS app

Open:

```text
Aegis-Admin/Aegis-Admin.xcodeproj
```

Select the `Aegis-Admin` scheme and run on **My Mac**.

The app window opens to the login screen. Sign in with an admin account from the backend.

---

## Local data expectations

The backend seed script creates the first admin user only. It does not seed learners, rooms, devices, or presence logs.

Because of that:

- Dashboard tables may be empty.
- Live Radar may show no rooms.
- Room map and occupant tables may be empty.

To fully test the UI locally, the project needs one of these:

- a demo seed script for learners, rooms, devices, and presence logs
- real learner/iPhone clients posting presence logs
- manual database inserts during development

---

## Useful files

Main app files:

```text
Aegis-Admin/Aegis-Admin/ContentView.swift
Aegis-Admin/Aegis-Admin/AdminModels.swift
Aegis-Admin/Aegis-Admin/AdminViewModels.swift
Aegis-Admin/Aegis-Admin/AegisAPIClient.swift
Aegis-Admin/Aegis-Admin/SessionStore.swift
```

Login hero asset:

```text
Aegis-Admin/Aegis-Admin/Assets.xcassets/LoginHero.imageset/
```

The default API base URL is defined in:

```text
Aegis-Admin/Aegis-Admin/AegisAPIClient.swift
```

---

## Build verification

From `Aegis-Admin/`:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Aegis-Admin.xcodeproj \
  -scheme Aegis-Admin \
  -configuration Debug \
  -derivedDataPath /tmp/aegis-admin-derived \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Xcode may print local CoreSimulator warnings. The important line is:

```text
** BUILD SUCCEEDED **
```

---

## Troubleshooting

### Login fails with connection error

Make sure the backend is running:

```bash
curl http://localhost:3000/health
```

If this fails, start the backend with `npm run dev` inside `Aegis-Backend`.

### Login says admin account is required

The backend returned a user whose `role` is not `admin`. Sign in with the seeded admin account or create an admin user.

### Dashboard or Live Radar is empty

This usually means the database has no learners, rooms, or presence logs. The normal seed only creates an admin.

### Settings fail to save

Check that the signed-in user is an admin and that the backend is running. Settings endpoints require an admin token.

### The app keeps returning to login

The stored refresh token may be expired, invalid, or rotated. Sign in again. The app will replace the Keychain token after a successful login.
