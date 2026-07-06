# Deploying Aegis Backend to Rocky Linux 9

End-to-end guide for deploying the Aegis backend to a Rocky Linux 9 VM. Assumes:

- **Rocky Linux 9** VM with a public IP (no domain yet)
- **Cloudflare** in front for HTTPS (TLS terminates at Cloudflare; VM speaks plain HTTP)
- **MySQL 8** installed on the same VM
- **systemd** managing the Node.js process

The end state: the backend runs as a systemd service, restarts on crashes and reboots, listens on port 3000 (plain HTTP), and is proxied by Cloudflare over HTTPS to the outside world.

If you get stuck, jump to [Troubleshooting](#troubleshooting) at the end.

---

## Prerequisites

Before touching the VM, make sure:

- You can SSH into the VM as a user with `sudo` privileges.
- You know the VM's public IPv4 address (call it `<VM_IP>` below).
- You have the deployment credentials handy: a strong `JWT_SECRET`, a `SEED_ADMIN_PASSWORD`, and a chosen MySQL password for the `aegis` database user.
- You have a Cloudflare account with the domain you'll expose (or you're happy to expose the raw IP for now — see [Step 8](#step-8--set-up-cloudflare-optional-but-recommended)).

Assume every command below runs as your non-root sudo user unless prefixed with `sudo`.

---

## Step 1 — Update the VM

```bash
sudo dnf update -y
sudo dnf install -y epel-release
sudo dnf install -y git curl vim firewalld policycoreutils-python-utils
sudo systemctl enable --now firewalld
```

- `epel-release` enables Extra Packages for Enterprise Linux (needed later for some tools if you extend).
- `firewalld` is Rocky's default firewall. We'll configure it below.
- `policycoreutils-python-utils` provides `semanage` for the one SELinux rule we'll need.

---

## Step 2 — Install Node.js 20

Rocky 9 ships an older Node in the default repos. Add NodeSource's Node 20 repo:

```bash
curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
sudo dnf install -y nodejs
```

Verify:

```bash
node --version    # should print v20.x.x
npm --version
```

---

## Step 3 — Install MySQL 8

Rocky 9's default MySQL is fine (it's MySQL 8):

```bash
sudo dnf install -y mysql-server
sudo systemctl enable --now mysqld
sudo systemctl status mysqld    # should say active (running)
```

Run the security script — set a **strong root password** and answer "y" to every prompt:

```bash
sudo mysql_secure_installation
```

Now create the application database and user. Replace `CHANGE_ME_STRONG_PASSWORD` with a real password you generate (`openssl rand -base64 24` is fine):

```bash
sudo mysql -u root -p
```

At the `mysql>` prompt:

```sql
CREATE DATABASE `AEGIS`;
CREATE USER 'aegis'@'localhost' IDENTIFIED BY 'CHANGE_ME_STRONG_PASSWORD';
GRANT ALL PRIVILEGES ON `AEGIS`.* TO 'aegis'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

Verify the user works:

```bash
mysql -u aegis -p AEGIS -e "SELECT 1;"
```

Should print `1` with no errors.

---

## Step 4 — Create a service user for the backend

Don't run Node as root. Create a dedicated system user that owns the code and the process:

```bash
sudo useradd --system --create-home --shell /bin/bash --home-dir /opt/aegis aegis
sudo -u aegis bash    # switch into the aegis user for the next steps
```

You are now `aegis@vm`. Prompt looks like `[aegis@... aegis]$`.

---

## Step 5 — Clone and install the backend

Still as the `aegis` user:

```bash
cd ~                                                    # /opt/aegis
git clone https://github.com/5-IE/aegis.git .           # clone into $HOME
cd Aegis-Backend
npm ci                                                  # exact install from package-lock.json
```

`npm ci` is stricter than `npm install` — it fails if `package-lock.json` disagrees with `package.json`, which is the correct behavior on a production host.

---

## Step 6 — Configure environment variables

Still as `aegis`:

```bash
cp .env.example .env
vim .env
```

Fill it in:

```env
PORT=3000
LOG_LEVEL=info

DB_HOST=localhost
DB_PORT=3306
DB_USER=aegis
DB_PASSWORD=CHANGE_ME_STRONG_PASSWORD          # matches Step 3
DB_NAME=AEGIS

JWT_SECRET=CHANGE_ME_AT_LEAST_32_CHARS         # see below

SEED_ADMIN_USERNAME=admin
SEED_ADMIN_PASSWORD=CHANGE_ME_ADMIN_PASSWORD   # you'll log in as this
SEED_ADMIN_EMAIL=admin@aegis.local
```

Generate a strong JWT secret on any machine with Node:

```bash
node -e "console.log(require('crypto').randomBytes(48).toString('base64'))"
```

Paste the output into `JWT_SECRET`. Must be ≥32 characters or the backend refuses to start.

Lock permissions so only the `aegis` user can read the file:

```bash
chmod 600 .env
ls -la .env      # should show -rw------- aegis aegis
```

Exit back to your sudo user:

```bash
exit             # leaves the aegis shell, returns to your login user
```

---

## Step 7 — Run migrations and seed the first admin

As your sudo user, run the migration and seed scripts under the `aegis` user's context. This uses the `.env` and creates the tables + first admin:

```bash
sudo -u aegis bash -c "cd /opt/aegis/Aegis-Backend && npm run migrate"
sudo -u aegis bash -c "cd /opt/aegis/Aegis-Backend && npm run seed"
```

Expected: migration log lines ending with "Migrations complete", then a "Seeded admin user" line.

Both scripts are idempotent — safe to re-run.

---

## Step 8 — systemd service

Create a unit file that runs the backend as the `aegis` user, restarts on crashes, and starts at boot:

```bash
sudo tee /etc/systemd/system/aegis-backend.service > /dev/null <<'EOF'
[Unit]
Description=Aegis Backend
Documentation=https://github.com/5-IE/aegis
After=network-online.target mysqld.service
Wants=network-online.target
Requires=mysqld.service

[Service]
Type=simple
User=aegis
Group=aegis
WorkingDirectory=/opt/aegis/Aegis-Backend
EnvironmentFile=/opt/aegis/Aegis-Backend/.env
ExecStart=/usr/bin/npx tsx src/server.ts
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=aegis-backend

# Hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/aegis/Aegis-Backend
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

[Install]
WantedBy=multi-user.target
EOF
```

Load, enable, start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable aegis-backend
sudo systemctl start aegis-backend
sudo systemctl status aegis-backend        # should say active (running)
```

Watch the logs:

```bash
sudo journalctl -u aegis-backend -f
```

You should see `{"level":30,"port":3000,"msg":"Aegis backend listening"}` (may be pretty-printed depending on env).

Ctrl+C exits the log viewer without stopping the service.

---

## Step 9 — Open port 3000 (temporary, for testing)

We'll close this again in Step 10 once Cloudflare is in front. For now:

```bash
sudo firewall-cmd --permanent --add-port=3000/tcp
sudo firewall-cmd --reload
sudo firewall-cmd --list-ports              # should include 3000/tcp
```

Also allow the Node process to bind to that port under SELinux (usually already allowed on port 3000, but here's the belt-and-suspenders):

```bash
# Only needed if SELinux is enforcing AND blocks the bind. Check first:
sudo getenforce
# If output is "Enforcing":
sudo semanage port -a -t http_port_t -p tcp 3000 2>/dev/null || true
```

The `|| true` swallows the "already added" error on re-runs.

Verify from your laptop:

```bash
curl http://<VM_IP>:3000/health
# Expected: {"status":"ok"}
```

Try logging in:

```bash
curl -X POST http://<VM_IP>:3000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"CHANGE_ME_ADMIN_PASSWORD"}'
```

You should get JSON with `access_token`, `refresh_token`, etc. If yes — the backend is fully deployed.

---

## Step 10 — Set up Cloudflare (optional but recommended)

Once you have a domain in Cloudflare pointing at the VM:

### 10a — DNS

In Cloudflare's dashboard, under your domain's **DNS** tab, add:

- **Type:** A
- **Name:** `api` (or `@`, or whatever subdomain you want)
- **IPv4 address:** `<VM_IP>`
- **Proxy status:** **Proxied** (orange cloud). This is what puts Cloudflare in front.

### 10b — SSL/TLS mode

Under **SSL/TLS → Overview**, set encryption mode to **Flexible** (Cloudflare ↔ browser is HTTPS; Cloudflare ↔ VM is HTTP).

If you can put a cert on the VM later, upgrade to **Full** or **Full (strict)** — but Flexible works today with zero VM setup and matches our "plain HTTP on backend" plan.

### 10c — Point the client apps at `https://api.yourdomain.com`

Test from your laptop:

```bash
curl https://api.yourdomain.com/health
# Expected: {"status":"ok"}
```

That's the full path from browser → Cloudflare (HTTPS) → VM (HTTP on port 3000).

### 10d — Restrict port 3000 to Cloudflare only

Cloudflare publishes their IP ranges at <https://www.cloudflare.com/ips-v4/>. Replace the "allow from anywhere" firewall rule from Step 9 with allow-from-Cloudflare-only:

```bash
sudo firewall-cmd --permanent --remove-port=3000/tcp

# Add each Cloudflare range. Fetch the current list:
for ip in $(curl -s https://www.cloudflare.com/ips-v4/); do
  sudo firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='$ip' port protocol='tcp' port='3000' accept"
done

sudo firewall-cmd --reload
sudo firewall-cmd --list-all
```

Now direct hits to `http://<VM_IP>:3000/health` from your laptop will **hang or time out** (correct behavior — the port is only reachable via Cloudflare's IPs). Requests via `https://api.yourdomain.com` still work.

**Trade-off:** if Cloudflare's IPs change, you'll need to refresh this list. Re-run the loop above whenever you notice traffic starting to fail. In practice they change rarely (~1x/year).

---

## Everyday operations

Once deployed, your ops loop:

```bash
sudo systemctl status aegis-backend                  # is it running?
sudo journalctl -u aegis-backend -f                   # tail logs
sudo journalctl -u aegis-backend --since "1 hour ago" # recent logs
sudo systemctl restart aegis-backend                  # kick it (after code update)
sudo systemctl stop aegis-backend                     # stop
sudo systemctl start aegis-backend                    # start
```

Deploy an update:

```bash
sudo -u aegis bash -c "cd /opt/aegis && git pull"
sudo -u aegis bash -c "cd /opt/aegis/Aegis-Backend && npm ci"
sudo -u aegis bash -c "cd /opt/aegis/Aegis-Backend && npm run migrate"
sudo systemctl restart aegis-backend
```

Rollback:

```bash
sudo -u aegis bash -c "cd /opt/aegis && git checkout <PREVIOUS_COMMIT>"
sudo -u aegis bash -c "cd /opt/aegis/Aegis-Backend && npm ci"
sudo systemctl restart aegis-backend
```

If the rollback commit is before a migration, that migration is still applied — new code needs to tolerate the newer schema, or you'll need to reverse the migration manually. Plan schema changes to be forward-compatible for one release.

---

## Nightly rollup

Attendance rollup runs from a script (`npm run rollup`), not the web server. Add a cron entry as the `aegis` user:

```bash
sudo crontab -u aegis -e
```

Add this line (runs at 3 AM VM-local time every day):

```cron
0 3 * * * cd /opt/aegis/Aegis-Backend && /usr/bin/npm run rollup >> /var/log/aegis/rollup.log 2>&1
```

Create the log directory:

```bash
sudo mkdir -p /var/log/aegis
sudo chown aegis:aegis /var/log/aegis
```

Rotate the log (create `/etc/logrotate.d/aegis`):

```bash
sudo tee /etc/logrotate.d/aegis > /dev/null <<'EOF'
/var/log/aegis/*.log {
    daily
    rotate 14
    compress
    missingok
    notifempty
    su aegis aegis
}
EOF
```

**Verify the timezone the cron runs in.** VM cron uses `date` timezone, which may not match your intended local TZ. Set it if needed:

```bash
sudo timedatectl set-timezone Asia/Jakarta
timedatectl status                    # confirm
```

The rollup script itself reads timezone from `SYSTEM_CONFIG.timezone` in the DB, not from the VM — so the DB-level TZ is what determines "yesterday". But you want the cron to fire at 3 AM *local* time so it runs after both AM and PM sessions have ended.

---

## Backups

Minimum: daily `mysqldump` to a local file, retained for 14 days. As root:

```bash
sudo tee /usr/local/bin/aegis-backup.sh > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail
BACKUP_DIR=/var/backups/aegis
mkdir -p "$BACKUP_DIR"
FILE="$BACKUP_DIR/aegis-$(date +%F-%H%M).sql.gz"
mysqldump --single-transaction --routines --triggers -u aegis -p"$DB_PASSWORD" AEGIS | gzip > "$FILE"
find "$BACKUP_DIR" -name 'aegis-*.sql.gz' -mtime +14 -delete
EOF
sudo chmod +x /usr/local/bin/aegis-backup.sh
```

Note: `$DB_PASSWORD` needs to be sourced from a secure location (don't paste it in the script). Simplest safe pattern is to read it from the aegis user's `.env` via a wrapper. For a minimal setup, create `/root/.aegis-backup-env`:

```bash
sudo tee /root/.aegis-backup-env > /dev/null <<'EOF'
export DB_PASSWORD=CHANGE_ME_STRONG_PASSWORD
EOF
sudo chmod 600 /root/.aegis-backup-env
```

And prepend `. /root/.aegis-backup-env` to the backup script.

Add to root's crontab:

```bash
sudo crontab -e
```

```cron
0 2 * * * /usr/local/bin/aegis-backup.sh
```

Runs at 2 AM daily, an hour before the rollup so we back up yesterday's fully-committed state.

**Test the backup can be restored** before you rely on it:

```bash
zcat /var/backups/aegis/aegis-<date>.sql.gz | mysql -u root -p AEGIS_TEST
```

(Restore into a scratch database to verify integrity, then drop `AEGIS_TEST`.)

For real workloads, ship these off-box — rsync to another server, upload to S3, whatever. A backup on the same VM protects against corruption, not disk loss.

---

## Troubleshooting

### `systemctl status aegis-backend` shows `failed`

Check the logs:

```bash
sudo journalctl -u aegis-backend -n 100 --no-pager
```

Common causes:

- **`Missing required env var: JWT_SECRET`** — the `.env` file is missing, unreadable by the `aegis` user, or `JWT_SECRET` is empty. Check `ls -la /opt/aegis/Aegis-Backend/.env` (should be `-rw------- aegis aegis`). Fix and `systemctl restart`.
- **`ECONNREFUSED 127.0.0.1:3306`** — MySQL isn't running. `sudo systemctl status mysqld`. Start it: `sudo systemctl start mysqld`. Wait a few seconds then `systemctl restart aegis-backend`.
- **`Access denied for user 'aegis'@'localhost'`** — DB password in `.env` doesn't match what MySQL knows. Reset it:
  ```bash
  sudo mysql -u root -p
  # in mysql:
  ALTER USER 'aegis'@'localhost' IDENTIFIED BY 'NEW_STRONG_PASSWORD';
  FLUSH PRIVILEGES;
  EXIT;
  ```
  Then update `.env` and restart.
- **`EADDRINUSE :::3000`** — something else is on 3000. `sudo lsof -i :3000` to find it. Kill it or change `PORT` in `.env`.

### `curl http://<VM_IP>:3000/health` hangs from your laptop

- Cloudflare's IP-only firewall from Step 10d is active — direct laptop hits are blocked (correct behavior). Test via `https://api.yourdomain.com/health` instead.
- If you're pre-Cloudflare and it still hangs: firewall issue. `sudo firewall-cmd --list-all` — port 3000 must appear.
- Or: cloud provider (AWS/GCP/Vultr) has its own security group blocking 3000. Check the provider dashboard.

### `curl https://api.yourdomain.com/health` returns 502 Bad Gateway

Cloudflare can reach its side but can't reach the VM's port 3000.

- Is `aegis-backend` running? `sudo systemctl status aegis-backend`
- Is the port open to Cloudflare? `sudo firewall-cmd --list-all` — should show either a plain 3000/tcp or the Cloudflare-restricted rich rules.
- Did the Cloudflare IP list change since you last configured the firewall? Re-run the loop in Step 10d.

### Migrations complain `Table 'X' already exists`

You dropped tables manually or the `SCHEMA_MIGRATIONS` tracker is out of sync. Nuclear option:

```bash
sudo mysql -u root -p -e "DROP DATABASE AEGIS;"
sudo -u aegis bash -c "cd /opt/aegis/Aegis-Backend && npm run migrate"
sudo -u aegis bash -c "cd /opt/aegis/Aegis-Backend && npm run seed"
sudo systemctl restart aegis-backend
```

**Warning: this deletes all data.** Only for pre-production. In production you'd restore from a `mysqldump` backup.

### The service restarts in a loop

`Restart=on-failure` with `RestartSec=5` means systemd retries indefinitely with 5s gaps if the process keeps exiting. You'll see it in `systemctl status`:

```
Active: activating (auto-restart) (Result: exit-code)
```

Look at the logs — the underlying error will be the same each time. Fix the cause (usually env vars or DB connectivity), then `systemctl restart` to break out of the loop cleanly.

### SELinux denies something (`Permission denied` in logs but files look fine)

```bash
sudo ausearch -m avc -ts recent | tail
```

If you see AVC denials mentioning `aegis-backend`, either fix the specific rule or, as a last resort:

```bash
sudo setenforce 0                   # temporary, until reboot
sudo journalctl -u aegis-backend -f # confirm this was the cause
sudo setenforce 1                   # turn back on
# Then figure out the actual rule you need
```

Rocky's default SELinux policy is generally friendly to Node processes in home directories. If you hit this consistently, `sudo audit2allow -a -M aegis-local` will generate a targeted policy module.

### `journalctl` output is huge / disk filling up

```bash
sudo journalctl --disk-usage       # how much are we using?
sudo journalctl --vacuum-time=7d   # trim to last 7 days
```

Persistent config in `/etc/systemd/journald.conf` — set `MaxRetentionSec=7day`.

---

## Security checklist before going live

- [ ] `JWT_SECRET` is ≥32 chars and generated with `crypto.randomBytes`, not a passphrase.
- [ ] `SEED_ADMIN_PASSWORD` in `.env` has been rotated *out* of `.env` after seed (change it via the API once you build the user-management endpoints, or via SQL directly).
- [ ] `.env` file mode is `0600` and owned by `aegis`.
- [ ] Port 3000 is firewalled to Cloudflare's IPs only (Step 10d).
- [ ] MySQL is bound to `127.0.0.1` (default). Confirm: `sudo ss -tlnp | grep 3306` — bind address should be `127.0.0.1`, NOT `0.0.0.0`.
- [ ] Root SSH login is disabled (Rocky default is disabled). Confirm `PermitRootLogin no` in `/etc/ssh/sshd_config`.
- [ ] Backups have been tested by restoring one.
- [ ] You can log in as the seeded admin AND you know how to revoke your own tokens if something leaks (`POST /auth/logout` per token, or DB-level `UPDATE REFRESH_TOKEN SET revoked_at = NOW()`).

---

## What next

- **Client apps** — point them at `https://api.yourdomain.com` (or `http://<VM_IP>:3000` pre-Cloudflare). See `docs/integrating-the-api.md`.
- **Monitoring** — this guide gives you `journalctl` and `systemctl status`. For real observability, wire in Prometheus + Grafana, or ship pino logs to a log aggregator. Out of scope here.
- **Zero-downtime deploys** — the current pattern has a ~2s gap during `systemctl restart`. For zero-downtime you'd need PM2 cluster mode or a second Node instance on port 3001 with Cloudflare Load Balancer. Also out of scope here.
