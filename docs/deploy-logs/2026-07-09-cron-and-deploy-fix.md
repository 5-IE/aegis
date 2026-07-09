# Aegis Backend — Cron Setup & Deploy Script Fix (2026-07-09)

## Nightly attendance rollup cron

Installed a cron job that runs the attendance rollup daily at 03:00 server time.

### What it does

Runs `scripts/rollupAttendance.ts` which:
1. For each learner, finds their first presence ping of the previous day
2. Compares against the session's `late_after` time
3. Writes one `ATTENDANCE_HISTORY` row: `early`, `late`, or `absent` (skips learners already marked `leave`)

### Files on the VM

| File | Purpose |
|------|---------|
| `/etc/cron.d/aegis-rollup` | Cron schedule (03:00 daily, runs as user `aegis`) |
| `/var/log/aegis-rollup.log` | Output log (owned by `aegis`) |
| `/etc/logrotate.d/aegis-rollup` | Weekly rotation, 4 weeks retained, compressed |

### Cron file contents

```
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin

0 3 * * * aegis cd /opt/aegis/aegis/Aegis-Backend && /usr/bin/npx tsx scripts/rollupAttendance.ts >> /var/log/aegis-rollup.log 2>&1
```

### Verification

```bash
# Manual test run (2026-07-09):
sudo -u aegis bash -c 'cd /opt/aegis/aegis/Aegis-Backend && npx tsx scripts/rollupAttendance.ts'
# Output: INFO Rollup complete { processed: 30, skipped_leave: 0 }

# crond is active and enabled on boot:
systemctl is-active crond  # → active
```

---

## Deploy script fix — `Access denied` on `systemctl restart`

### Problem

Running `aegis-deploy` with `sudo -n` worked (whole script as root), but anyone running it with a password prompt at the start got "Access denied" on `systemctl restart aegis-backend` because the inner `systemctl` ran as the invoking user, and polkit denied it.

### Root cause

The script used bare `systemctl restart aegis-backend` without `sudo`. The sudoers rule only covered `/usr/local/bin/aegis-deploy` itself — so if the script wasn't invoked as root by `sudo -n`, its inner systemctl calls ran unprivileged.

### Fix

1. Added `sudo` in front of `systemctl restart/is-active` inside the deploy script
2. Extended `/etc/sudoers.d/aegis-deploy` to also allow `freuch` to run systemctl for aegis-backend without a password:

```
freuch ALL=(root) NOPASSWD: /usr/local/bin/aegis-deploy
freuch ALL=(root) NOPASSWD: /usr/bin/systemctl restart aegis-backend
freuch ALL=(root) NOPASSWD: /usr/bin/systemctl is-active aegis-backend
freuch ALL=(root) NOPASSWD: /usr/bin/systemctl status aegis-backend
```

### Verification

```bash
# From local machine (key auth, no sshpass needed):
ssh -p 484 freuch@10.64.58.125 'sudo -n /usr/local/bin/aegis-deploy'
# ==> Restarting service...
# active
# {"status":"ok"}
# ==> Deployed 48a98fa ...
```

Both `sudo -n aegis-deploy` (passwordless from SSH) and manual `sudo aegis-deploy` (with password prompt) now work correctly.
