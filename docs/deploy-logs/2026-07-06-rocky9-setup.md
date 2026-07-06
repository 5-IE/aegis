# Aegis Backend — Rocky 9 Deploy Log (2026-07-06)

Live deployment transcript.

**Target VM:**
- Host: `10.64.58.125:484` (private network)
- User: `freuch` (has full sudo via password)
- OS: Rocky Linux release 9.8 (Blue Onyx)
- Arch: aarch64 (ARM64)
- Kernel: 5.14.0-687.17.1.el9_8.aarch64
- Hostname: `10-64-58-125.0200.binb.id.iosda.org`
- Disk: 38G total, 2.2G used before install
- RAM: 7.4G

## Pre-existing on VM
- Node 24.18.0, npm 11.16.0 (newer than the 20+ minimum — fine)
- No git, no MySQL, no nginx
- firewalld inactive
- Only port 484 (SSH) listening initially

## Summary of what was installed / created

| Item | Value |
|---|---|
| Packages installed via `dnf` | `git`, `mysql-server` (8.0.46 aarch64) |
| MySQL service | `mysqld` enabled + running |
| MySQL DB | `AEGIS` |
| MySQL user | `aegis@localhost` (random 30-char password) |
| System user | `aegis` with home `/opt/aegis` |
| Repo cloned to | `/opt/aegis/aegis` (github.com/5-IE/aegis, branch `main`) |
| Env file | `/opt/aegis/aegis/Aegis-Backend/.env`, owner `aegis:aegis`, mode `0600` |
| systemd unit | `/etc/systemd/system/aegis-backend.service` |
| Node process | `npx tsx src/server.ts` running under user `aegis` |
| Listening port | `3000` (all interfaces) |
| Seeded admin | `admin` / `admin@aegis.local` (id=1, password in `.env` on VM) |

## Verification

- `curl http://localhost:3000/health` → `{"status":"ok"}` ✅
- `POST /auth/login` with seeded admin → returns JWT access + refresh tokens ✅
- `systemctl is-active aegis-backend` → `active`

## Key commands executed

### Connectivity + package install
```bash
# from local (macOS): ssh with password auth forced to bypass local key attempts
sshpass -p '@123' ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no -p 484 freuch@10.64.58.125 '...'

# on VM (via sudo -S using same password)
echo '@123' | sudo -S dnf install -y git
echo '@123' | sudo -S dnf install -y mysql-server
echo '@123' | sudo -S systemctl enable --now mysqld
```

### DB setup
```sql
CREATE DATABASE IF NOT EXISTS AEGIS;
CREATE USER IF NOT EXISTS 'aegis'@'localhost' IDENTIFIED BY '<RANDOM_30_CHAR>';
GRANT ALL PRIVILEGES ON AEGIS.* TO 'aegis'@'localhost';
FLUSH PRIVILEGES;
```

### System user + clone + install
```bash
sudo useradd --system --create-home --shell /bin/bash --home-dir /opt/aegis aegis
sudo -u aegis git clone https://github.com/5-IE/aegis.git /opt/aegis/aegis
sudo -u aegis bash -c 'cd /opt/aegis/aegis/Aegis-Backend && npm ci'

# npm 11 blocks install scripts by default — bcrypt native binding needs it
sudo -u aegis bash -c 'cd /opt/aegis/aegis/Aegis-Backend && npm approve-scripts bcrypt esbuild'
```

### .env creation
Built on local machine with random secrets, then `scp`'d to `/tmp/aegis.env` on VM and `sudo mv` to final location with `chown aegis:aegis` and `chmod 600`.

### Migrations + seed
```bash
sudo -u aegis bash -c 'cd /opt/aegis/aegis/Aegis-Backend && npm run migrate'
sudo -u aegis bash -c 'cd /opt/aegis/aegis/Aegis-Backend && npm run seed'
```

### systemd unit
`/etc/systemd/system/aegis-backend.service` (see `docs/deployment-rocky9.md` for the template used).

Enabled + started:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now aegis-backend
sudo systemctl status aegis-backend    # → active (running)
```

## Issues hit during deploy

1. **`sshpass` not installed locally.** Fixed with `brew install sshpass`.
2. **SSH auth failed with "Too many authentication failures"** on first attempt — local key attempts were exhausting the auth limit before password. Fixed with `-o PreferredAuthentications=password -o PubkeyAuthentication=no`.
3. **npm 11 blocked bcrypt's install script**, resulting in a broken native binding. Fixed with `npm approve-scripts bcrypt esbuild`.
4. **Migration runner failed on `CREATE DATABASE AEGIS`** because I had pre-created the DB manually. Fixed by dropping the empty DB and letting migration 0001 bootstrap it fresh. Migrations then applied 0001–0005 cleanly.
5. **First `.env` was uploaded with an empty `SEED_ADMIN_PASSWORD` line** due to a variable substitution bug in the heredoc. Fixed by rebuilding the file locally and re-uploading.

## Secrets

All secrets are stored:
- On the VM: `/opt/aegis/aegis/Aegis-Backend/.env` (owner `aegis:aegis`, mode `0600`)
- On the local dev machine that ran this deploy: `/tmp/aegis-secrets.env` (temporary — delete after deploy)

**Recommended next steps** (not blocking):
1. Rotate the seeded admin password by logging in and using the (still-pending) `PUT /api/v1/admin/users/:id/password` endpoint once the user-crud branch merges.
2. Delete `/tmp/aegis-secrets.env` on the deploy laptop.
3. Set up SSH key auth + `PasswordAuthentication no` in `/etc/ssh/sshd_config`.
4. If exposing to public internet: put Cloudflare / nginx in front of port 3000 and firewall the port to only Cloudflare IPs — see `docs/deployment-rocky9.md` step 10.
5. On the VM, `journalctl -u aegis-backend -f` tails live logs.

## Operational cheat-sheet

```bash
# Status
sudo systemctl status aegis-backend

# Logs
sudo journalctl -u aegis-backend -f
sudo journalctl -u aegis-backend --since "10 minutes ago"

# Restart after code update
sudo -u aegis bash -c 'cd /opt/aegis/aegis && git pull && cd Aegis-Backend && npm ci && npm run migrate'
sudo systemctl restart aegis-backend

# Stop / start
sudo systemctl stop aegis-backend
sudo systemctl start aegis-backend
```

## Post-deploy tweaks (applied after initial setup)

### Firewall — open port 3000 for API access

`firewalld` was running and blocking port 3000. Fixed:

```bash
sudo firewall-cmd --permanent --add-port=3000/tcp
sudo firewall-cmd --reload
```

### MySQL exposed on LAN for remote client access

For team access via MySQL Workbench / DBeaver from laptops on the same private network:

```bash
# 1. Rebind MySQL to 0.0.0.0
sudo tee -a /etc/my.cnf.d/mysql-server.cnf > /dev/null <<'EOF'

[mysqld]
bind-address = 0.0.0.0
EOF
sudo systemctl restart mysqld

# 2. Create aegis@% user
sudo mysql -e "
  CREATE USER IF NOT EXISTS 'aegis'@'%' IDENTIFIED BY '<DB_PASSWORD>';
  GRANT ALL PRIVILEGES ON AEGIS.* TO 'aegis'@'%';
  FLUSH PRIVILEGES;
"

# 3. Open MySQL port
sudo firewall-cmd --permanent --add-port=3306/tcp
sudo firewall-cmd --reload
```

Client connection details:

| Field | Value |
|---|---|
| Host | `10.64.58.125` |
| Port | `3306` |
| User | `aegis` |
| Password | as stored in `/opt/aegis/aegis/Aegis-Backend/.env` |
| Database | `AEGIS` |

See [`docs/deployment-rocky9.md` § Remote MySQL access](../deployment-rocky9.md#remote-mysql-access) for details and security notes.

