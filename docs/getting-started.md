# Getting Started — Aegis Backend

This guide walks you through running the Aegis backend on your laptop, seeding a first admin, and confirming everything works. You'll end up with the API listening on `http://localhost:3000` and a working admin login.

If you get stuck, jump to [Troubleshooting](#troubleshooting) at the bottom.

---

## Prerequisites

Install these first if you don't have them:

- **Node.js 20 or newer.** Check with `node --version`. Get it from [nodejs.org](https://nodejs.org/) or via [nvm](https://github.com/nvm-sh/nvm).
- **Git.** `git --version`.
- **A terminal.** macOS Terminal or iTerm2; Windows PowerShell or WSL; Linux any shell.
- **MySQL 8.** Two options — pick one:
  - **Option A: Docker Desktop** (recommended if you don't already have MySQL). Install [Docker Desktop](https://www.docker.com/products/docker-desktop/).
  - **Option B: Native install** — install MySQL 8 directly on your machine.

You do NOT need Xcode, iOS simulators, or anything Apple-specific for the backend. Those are for building the iPhone/macOS apps.

---

## Step 1 — Clone the repo

```bash
git clone https://github.com/5-IE/aegis.git
cd aegis
```

The backend lives in `Aegis-Backend/`. Everything below runs from there unless noted.

```bash
cd Aegis-Backend
```

---

## Step 2 — Install dependencies

```bash
npm install
```

This downloads all the Node.js packages the backend needs. Takes ~30 seconds on a fresh install. You'll see some `npm warn` lines about dev dependencies — those are harmless.

---

## Step 3 — Start MySQL

Pick the option that matches what you installed above.

### Option A — Docker (recommended)

From the **repo root** (one directory up from `Aegis-Backend`), run:

```bash
cd ..                    # go to the repo root
docker compose up -d     # starts MySQL in the background
```

The first time this runs, Docker downloads MySQL (~600 MB). After that, it takes seconds.

Check it's healthy:

```bash
docker compose ps
```

You should see `aegis-mysql` with status `running (healthy)`. The container exposes MySQL on `localhost:3306` with:

- Database: `AEGIS`
- User: `aegis`
- Password: `aegispassword`
- Root password: `rootpassword`

To stop MySQL when you're done for the day: `docker compose stop`. To completely remove it (and all data): `docker compose down -v`.

Now `cd Aegis-Backend` again to continue.

### Option B — Native MySQL install

Install MySQL 8 the way that fits your OS:

- **macOS (Homebrew):**
  ```bash
  brew install mysql
  brew services start mysql
  ```
- **Linux (Ubuntu/Debian):**
  ```bash
  sudo apt update && sudo apt install mysql-server
  sudo systemctl start mysql
  ```
- **Windows:** Download the [MySQL 8 installer](https://dev.mysql.com/downloads/installer/), run it, choose "Developer Default".

Once MySQL is running, create the database and a user for the backend:

```bash
mysql -u root -p
```

Then at the `mysql>` prompt:

```sql
CREATE USER 'aegis'@'localhost' IDENTIFIED BY 'aegispassword';
GRANT ALL PRIVILEGES ON AEGIS.* TO 'aegis'@'localhost';
GRANT CREATE ON *.* TO 'aegis'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

(The last two GRANT lines let the migration script create the `AEGIS` database on first run.)

---

## Step 4 — Configure environment variables

The backend reads config from a `.env` file (which is gitignored — never commit it). Copy the example:

```bash
cp .env.example .env
```

Now open `.env` in your editor and fill in the values. Here's what everything means:

```env
PORT=3000                                # port the API listens on
LOG_LEVEL=info                           # pino log level: trace|debug|info|warn|error

DB_HOST=localhost                        # MySQL host
DB_PORT=3306                             # MySQL port (default 3306)
DB_USER=aegis                            # MySQL user we created above
DB_PASSWORD=aegispassword                # matches the password above
DB_NAME=AEGIS                            # matches the database name

JWT_SECRET=<paste a random 64-char string here>   # signs access tokens

SEED_ADMIN_USERNAME=admin                # first admin's username
SEED_ADMIN_PASSWORD=changeme             # first admin's password
SEED_ADMIN_EMAIL=admin@aegis.local       # first admin's email
```

**Generate a strong `JWT_SECRET`:**

```bash
node -e "console.log(require('crypto').randomBytes(48).toString('base64'))"
```

Paste the output as `JWT_SECRET`. It must be at least 32 characters or the backend will refuse to start.

---

## Step 5 — Run the migrations

Migrations create the database tables. Run them once:

```bash
npm run migrate
```

You should see log lines like:

```
{"level":30,"file":"0001_init.sql","msg":"Applying"}
{"level":30,"file":"0002_bcrypt_password.sql","msg":"Applying"}
...
{"level":30,"msg":"Migrations complete"}
```

Safe to re-run — already-applied migrations are skipped.

---

## Step 6 — Seed the first admin

The seed script creates a single admin user based on your `.env` values so you can log in.

```bash
npm run seed
```

You should see:

```
{"level":30,"username":"admin","id":1,"msg":"Seeded admin user"}
```

Idempotent — re-running says "Admin already exists — skipping".

---

## Step 7 — Start the dev server

```bash
npm run dev
```

You should see:

```
{"level":30,"port":3000,"msg":"Aegis backend listening"}
```

The API is now live at `http://localhost:3000`. Leave this terminal running.

---

## Step 8 — Verify it works

In a **new terminal**, run:

```bash
curl http://localhost:3000/health
```

Expected output:

```json
{"status":"ok"}
```

Now try logging in as the admin you seeded:

```bash
curl -X POST http://localhost:3000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"changeme"}'
```

You should get back a JSON object with `access_token`, `refresh_token`, `expires_in`, and a `user` object. If you do — you're done. Read [Integrating the API](integrating-the-api.md) next.

---

## Everyday commands

Once the initial setup is done, your daily loop is:

```bash
# start MySQL (Docker option)
docker compose up -d

# in Aegis-Backend/
npm run dev        # runs the backend with auto-reload on file changes

# ...code...
npm test           # run the test suite
npm run lint       # check for lint errors
```

Stop the server with Ctrl+C. Stop MySQL when you're done: `docker compose stop` (Docker) — native MySQL keeps running in the background.

---

## Troubleshooting

### `Missing required env var: JWT_SECRET`

Your `.env` file is missing or `JWT_SECRET` is empty. Copy `.env.example` to `.env` and generate a secret with the `node -e` command in Step 4.

### `JWT_SECRET must be at least 32 characters`

Same fix — generate a longer secret with the `node -e` command.

### `Error: connect ECONNREFUSED 127.0.0.1:3306`

MySQL isn't running or isn't listening on port 3306.

- **Docker:** run `docker compose up -d` from the repo root, then `docker compose ps` to confirm status is `healthy`.
- **Native macOS:** `brew services list` — if MySQL says `stopped`, run `brew services start mysql`.
- **Native Linux:** `sudo systemctl status mysql`.
- **Port in use:** something else is on 3306. Change `DB_PORT` in `.env` and use the new port when starting your MySQL.

### `Access denied for user 'aegis'@'localhost'`

The MySQL user doesn't exist or the password doesn't match your `.env`.

- **Docker:** you shouldn't hit this — the container creates the user automatically. Double-check `.env` values match Step 3.
- **Native:** re-run the `CREATE USER` / `GRANT` block from Step 3 Option B.

### `Error: listen EADDRINUSE: address already in use :::3000`

Something else is on port 3000. Either kill it or change `PORT=3001` in `.env` and restart.

### `npm run migrate` fails on second run with `Table 'X' already exists`

The `SCHEMA_MIGRATIONS` tracking table is out of sync — usually because someone dropped tables manually. Nuke the database and re-run:

- **Docker:** `docker compose down -v && docker compose up -d && sleep 5 && npm run migrate`
- **Native:** `mysql -u root -p -e "DROP DATABASE AEGIS;"` then `npm run migrate` (the runner recreates the database).

### 401 immediately after `/auth/login` succeeds

You're either:
- Not sending the `Authorization: Bearer <access_token>` header on the follow-up request, OR
- Sending the `refresh_token` instead of the `access_token` (they're different fields in the login response).

### Tests fail with `Cannot find module ...`

Run `npm install` again. Sometimes editor caches go stale after a `git pull`.

### `Error: ER_NOT_SUPPORTED_AUTH_MODE`

Old MySQL client / new server auth plugin mismatch. Not usually a problem with MySQL 8 + our `mysql2` package. If it happens, run this in MySQL as root:

```sql
ALTER USER 'aegis'@'localhost' IDENTIFIED WITH mysql_native_password BY 'aegispassword';
FLUSH PRIVILEGES;
```

### The dev server won't stop on Ctrl+C

Ctrl+C twice usually gets it. If not: find the process — `lsof -i :3000` on macOS/Linux — and `kill -9 <pid>`.

---

## What next

- **[Integrating the API](integrating-the-api.md)** — how to authenticate, call endpoints, refresh tokens, and integrate from a client app.
- **[API Reference](api-reference.html)** — the full endpoint catalogue. Open it in a browser.
