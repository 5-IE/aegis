# Deploying updates to the production VM

How to ship new commits from `main` to the Rocky Linux 9 VM. For first-time setup, see [`deployment-rocky9.md`](deployment-rocky9.md); for what was actually done on the box, see [`deploy-logs/2026-07-06-rocky9-setup.md`](deploy-logs/2026-07-06-rocky9-setup.md).

## TL;DR — one command

The VM has `/usr/local/bin/aegis-deploy` installed (fetch → ff-merge main → `npm ci` if the lockfile changed → migrate → restart → health check). `freuch` can run it via passwordless sudo, so from your machine:

```bash
ssh -p 484 freuch@10.64.58.125 sudo -n aegis-deploy
```

Deploy a specific commit/branch instead of main: `... sudo -n aegis-deploy <commit-ish>`.

The script's source of truth lives in the repo at [`Aegis-Backend/scripts/deploy/aegis-deploy`](../Aegis-Backend/scripts/deploy/aegis-deploy). If you change it, reinstall it on the VM:

```bash
scp -P 484 Aegis-Backend/scripts/deploy/aegis-deploy freuch@10.64.58.125:/tmp/aegis-deploy
ssh -p 484 freuch@10.64.58.125 "sudo install -m 755 /tmp/aegis-deploy /usr/local/bin/aegis-deploy"
```

(The passwordless-sudo rule in `/etc/sudoers.d/aegis-deploy` covers only this exact path, so keep the install location.)

Make it a local alias (`~/.zshrc`):

```bash
alias aegis-deploy="ssh -p 484 freuch@10.64.58.125 sudo -n aegis-deploy"
```

The manual steps below remain as reference for when the script can't be used or you need to intervene by hand.

## Facts about the box

| Item | Value |
|---|---|
| SSH | `freuch@10.64.58.125`, port **484** (password auth) |
| Repo checkout | `/opt/aegis/aegis` (owner: system user `aegis`) |
| Backend dir | `/opt/aegis/aegis/Aegis-Backend` |
| Service | `aegis-backend` (systemd, runs `npx tsx src/server.ts` as user `aegis`) |
| Env file | `/opt/aegis/aegis/Aegis-Backend/.env` (mode 0600, only `aegis` can read) |
| API | port 3000, health check at `/health` |

Note: the checkout and `.env` are owned by the `aegis` system user — `freuch` cannot even `cd` into the repo without sudo. Every repo command below therefore goes through `sudo -u aegis`.

> The "Deploy an update" snippet in `deployment-rocky9.md` uses `/opt/aegis` as the repo path; the real path on the VM is `/opt/aegis/aegis`. Use the paths in this guide.

## Standard update (no schema/dependency changes)

SSH in:

```bash
ssh -p 484 freuch@10.64.58.125
```

Then on the VM:

```bash
# 1. Pull the new commits
sudo -u aegis bash -c "cd /opt/aegis/aegis && git pull --ff-only origin main"

# 2. Restart the service (tsx runs TS directly — no build step)
sudo systemctl restart aegis-backend

# 3. Verify
systemctl is-active aegis-backend          # → active
curl -s http://localhost:3000/health       # → {"status":"ok"}
sudo journalctl -u aegis-backend -n 20     # startup logs, check for errors
```

That's the whole loop for code-only changes. Because the service runs TypeScript via `tsx`, there is no compile step — pull + restart is enough.

## When `package.json` / `package-lock.json` changed

Add an install step between pull and restart:

```bash
sudo -u aegis bash -c "cd /opt/aegis/aegis/Aegis-Backend && npm ci"
```

Heads-up: npm 11 on the VM blocks postinstall scripts by default. If a native dependency was added or bumped (like `bcrypt`), approve it or its binding won't build:

```bash
sudo -u aegis bash -c "cd /opt/aegis/aegis/Aegis-Backend && npm approve-scripts <package>"
```

## When there are new migrations

Run migrations after pull/install, before restart:

```bash
sudo -u aegis bash -c "cd /opt/aegis/aegis/Aegis-Backend && npm run migrate"
```

Migrations read DB credentials from the `.env` in that directory; running as the `aegis` user is what makes that file readable.

## When `.env` needs a new variable

Edit as root (the file is 0600 `aegis:aegis`):

```bash
sudo -e /opt/aegis/aegis/Aegis-Backend/.env
sudo systemctl restart aegis-backend
```

## Verify from your machine

```bash
curl -s http://10.64.58.125:3000/health
curl -s http://10.64.58.125:3000/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"<current admin password>"}' \
  | head -c 120   # expect access_token JSON, not an error
```

## Rollback

```bash
sudo -u aegis bash -c "cd /opt/aegis/aegis && git log --oneline -5"   # find the good commit
sudo -u aegis bash -c "cd /opt/aegis/aegis && git checkout <COMMIT>"
sudo -u aegis bash -c "cd /opt/aegis/aegis/Aegis-Backend && npm ci"   # only if deps changed
sudo systemctl restart aegis-backend
```

Applied migrations are NOT rolled back by a code rollback. If the bad release included a migration, the old code must tolerate the new schema, or you reverse the migration by hand in MySQL. To return to tracking main afterward: `git checkout main && git pull --ff-only`.

## Side effects of restarting

- **Rate limiter resets.** The auth rate limiter is in-memory, so a restart clears any "too many requests" lockouts (and, conversely, loses legitimate throttling state).
- **In-flight requests drop.** There is no graceful drain; the admin/learner apps will retry on next poll.
- **Sessions survive.** JWTs and refresh tokens live in MySQL/are stateless, so nobody gets logged out.

## Troubleshooting

- Service won't start → `sudo journalctl -u aegis-backend -n 50`. The most common cause is a missing required env var (config throws `Missing required env var: ...` on boot).
- `git pull` fails with local changes → someone edited files on the VM directly. `sudo -u aegis bash -c "cd /opt/aegis/aegis && git status"` and either commit/stash or `git checkout -- <file>` them, then pull again.
- Health check OK but API errors → check MySQL: `systemctl is-active mysqld`, then app logs.



sudo npx tsx -e "
  const { hashPassword } = await import('./src/services/passwordService.js');
  const { updateUserPassword } = await import('./src/db/queries/userQueries.js');
  await updateUserPassword(1, await hashPassword('admin@aegis.local'));
  console.log('done'); process.exit(0);
  "