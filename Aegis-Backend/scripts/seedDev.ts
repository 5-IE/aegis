import 'dotenv/config';
import { logger } from '../src/lib/logger.js';
import { pool } from '../src/db/pool.js';
import { hashPassword } from '../src/services/passwordService.js';
import { RowDataPacket, ResultSetHeader } from 'mysql2';

/**
 * Dev fixtures: populate every non-auth table with realistic demo data
 * so UI screens have something to show during integration.
 *
 * Volume (small): 1 admin + 30 learners, 4 rooms, 4 devices, ~30 days of presence.
 *
 * Guarded by AEGIS_SEED_DEV=1 or --force. Destructive: truncates all
 * mutable tables before seeding.
 *
 * Determinism: uses a seeded PRNG so the same run twice produces the
 * same data. Change SEED_RNG to reshuffle.
 */

// ============================================================================
// Config
// ============================================================================

const CONFIG = {
  admins: 1,
  learners: 30,
  rooms: 4,
  daysOfHistory: 30,
  timezone: 'Asia/Jakarta',
  // password used for every seeded user; NOT for production
  devPassword: 'password123',
  // realism knobs
  amStart: '08:00:00',
  amLateAfter: '08:15:00',
  amEnd: '12:00:00',
  pmStart: '13:00:00',
  pmLateAfter: '13:15:00',
  pmEnd: '17:00:00',
  pingIntervalMinutes: 5,
  // probabilities per learner per day
  pAbsent: 0.05,
  pLeave: 0.03,
  pLate: 0.15,
};

const SEED_RNG = 1337;

// ============================================================================
// Guards
// ============================================================================

function isGuarded(): boolean {
  if (process.env.AEGIS_SEED_DEV === '1') return true;
  if (process.argv.includes('--force')) return true;
  return false;
}

// ============================================================================
// Deterministic PRNG (mulberry32)
// ============================================================================

function makeRng(seed: number): () => number {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const rng = makeRng(SEED_RNG);
const randInt = (lo: number, hi: number) => lo + Math.floor(rng() * (hi - lo + 1));
const pick = <T>(arr: T[]): T => arr[Math.floor(rng() * arr.length)];
const chance = (p: number) => rng() < p;

// ============================================================================
// Test fixture data
// ============================================================================

const FIRST_NAMES = [
  'Alice', 'Bob', 'Chloe', 'Daniel', 'Ethan', 'Fatima', 'Grace', 'Hasan',
  'Isabella', 'Jared', 'Kaia', 'Leo', 'Maya', 'Nadia', 'Oscar', 'Priya',
  'Quinn', 'Rania', 'Sam', 'Tara', 'Umar', 'Vera', 'Wira', 'Xavier',
  'Yasmin', 'Zayn', 'Ari', 'Beni', 'Cinta', 'Dewi', 'Eko', 'Farah',
  'Gani', 'Hana', 'Indra', 'Joan', 'Kirana', 'Luki',
];

const LAST_NAMES = [
  'Sudirman', 'Wijaya', 'Susanto', 'Kurnia', 'Halim', 'Setiawan', 'Nugroho',
  'Pratama', 'Anggraini', 'Lestari', 'Handoko', 'Widodo', 'Saputra',
  'Ramadhan', 'Iskandar', 'Sitorus', 'Panjaitan', 'Marpaung',
];

const ROOM_NAMES = [
  'Lab 3.01',
  'Lab 3.02',
  'Lab 3.03',
  'Lecture Hall A',
  'Studio 2B',
  'Innovation Lab',
];

// ============================================================================
// Timezone helpers (copy of statusService logic for isolation)
// ============================================================================

function parts(date: Date, tz: string) {
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
  });
  const out: Record<string, string> = {};
  for (const p of fmt.formatToParts(date)) {
    if (p.type !== 'literal') out[p.type] = p.value;
  }
  return {
    y: Number.parseInt(out.year, 10),
    m: Number.parseInt(out.month, 10),
    d: Number.parseInt(out.day, 10),
    h: Number.parseInt(out.hour === '24' ? '0' : out.hour, 10),
    mi: Number.parseInt(out.minute, 10),
    s: Number.parseInt(out.second, 10),
  };
}

function combineLocalDateAndTime(localDate: string, timeHHMMSS: string, tz: string): Date {
  const [y, mo, d] = localDate.split('-').map((x) => Number.parseInt(x, 10));
  const [h, mi, s] = timeHHMMSS.split(':').map((x) => Number.parseInt(x, 10));
  let guess = Date.UTC(y, mo - 1, d, h, mi, s);
  for (let i = 0; i < 3; i++) {
    const p = parts(new Date(guess), tz);
    const target = Date.UTC(y, mo - 1, d, h, mi, s);
    const actual = Date.UTC(p.y, p.m - 1, p.d, p.h, p.mi, p.s);
    const diff = target - actual;
    if (diff === 0) break;
    guess += diff;
  }
  return new Date(guess);
}

function localDateStr(now: Date, tz: string): string {
  const p = parts(now, tz);
  return `${p.y}-${String(p.m).padStart(2, '0')}-${String(p.d).padStart(2, '0')}`;
}

function subtractLocalDays(dateStr: string, days: number, tz: string): string {
  const anchor = combineLocalDateAndTime(dateStr, '12:00:00', tz);
  const earlier = new Date(anchor.getTime() - days * 24 * 60 * 60 * 1000);
  return localDateStr(earlier, tz);
}

// ============================================================================
// Seed
// ============================================================================

async function seedUsers(): Promise<{ adminIds: number[]; learnerIds: number[]; learnerSessions: Map<number, 'AM' | 'PM'> }> {
  logger.info({ admins: CONFIG.admins, learners: CONFIG.learners }, 'Seeding USER');
  const passwordHash = await hashPassword(CONFIG.devPassword);

  const adminIds: number[] = [];
  for (let i = 0; i < CONFIG.admins; i++) {
    const [r] = await pool.query<ResultSetHeader>(
      `INSERT INTO \`USER\` (\`username\`, \`password\`, \`email\`, \`role\`, \`first_name\`, \`last_name\`, \`session\`)
       VALUES (?, ?, ?, 'admin', ?, ?, 'AM')`,
      [
        i === 0 ? 'admin' : `admin${i + 1}`,
        passwordHash,
        i === 0 ? 'admin@aegis.local' : `admin${i + 1}@aegis.local`,
        pick(FIRST_NAMES),
        pick(LAST_NAMES),
      ],
    );
    adminIds.push(r.insertId);
  }

  const learnerIds: number[] = [];
  const learnerSessions = new Map<number, 'AM' | 'PM'>();
  const usedUsernames = new Set<string>();
  for (let i = 0; i < CONFIG.learners; i++) {
    const first = pick(FIRST_NAMES);
    const last = pick(LAST_NAMES);
    const base = `${first.toLowerCase()}.${last.toLowerCase()}`;
    let username = base;
    let n = 1;
    while (usedUsernames.has(username)) {
      username = `${base}${++n}`;
    }
    usedUsernames.add(username);
    const session = chance(0.5) ? 'AM' : 'PM';
    const [r] = await pool.query<ResultSetHeader>(
      `INSERT INTO \`USER\` (\`username\`, \`password\`, \`email\`, \`role\`, \`first_name\`, \`last_name\`, \`session\`)
       VALUES (?, ?, ?, 'learner', ?, ?, ?)`,
      [username, passwordHash, `${username}@aegis.local`, first, last, session],
    );
    learnerIds.push(r.insertId);
    learnerSessions.set(r.insertId, session);
  }

  logger.info({ adminCount: adminIds.length, learnerCount: learnerIds.length }, 'USER seeded');
  return { adminIds, learnerIds, learnerSessions };
}

async function seedRoomsAndDevices(): Promise<{ roomIds: number[] }> {
  logger.info({ rooms: CONFIG.rooms }, 'Seeding ROOM + DEVICE');
  const roomIds: number[] = [];
  for (let i = 0; i < CONFIG.rooms; i++) {
    const [r] = await pool.query<ResultSetHeader>(
      'INSERT INTO `ROOM` (`name`) VALUES (?)',
      [ROOM_NAMES[i % ROOM_NAMES.length]],
    );
    roomIds.push(r.insertId);
    await pool.query<ResultSetHeader>(
      'INSERT INTO `DEVICE` (`name`, `identifier`, `id_room`) VALUES (?, ?, ?)',
      [`iBeacon ${i + 1}`, `1:${1000 + i}`, r.insertId],
    );
  }
  // Add one unassigned device to prove the /beacons filter excludes it
  await pool.query<ResultSetHeader>(
    'INSERT INTO `DEVICE` (`name`, `identifier`, `id_room`) VALUES (?, ?, NULL)',
    ['iBeacon Spare', '1:9999'],
  );
  logger.info({ roomCount: roomIds.length, devices: CONFIG.rooms + 1 }, 'ROOM + DEVICE seeded');
  return { roomIds };
}

interface LearnerDayOutcome {
  status: 'early' | 'late' | 'absent' | 'leave';
  firstPingUtc: Date | null;
  lastPingUtc: Date | null;
}

async function seedPresenceAndHistory(
  learnerIds: number[],
  learnerSessions: Map<number, 'AM' | 'PM'>,
  roomIds: number[],
): Promise<void> {
  logger.info({ days: CONFIG.daysOfHistory }, 'Seeding PRESENCE_LOG + ATTENDANCE_HISTORY');

  const todayLocal = localDateStr(new Date(), CONFIG.timezone);
  const historyRows: Array<[number, string, string]> = [];
  const presenceRows: Array<[number, number, Date, number, number, number]> = [];

  for (let d = CONFIG.daysOfHistory - 1; d >= 0; d--) {
    const dateStr = subtractLocalDays(todayLocal, d, CONFIG.timezone);
    const isToday = d === 0;

    for (const userId of learnerIds) {
      const session = learnerSessions.get(userId)!;
      const start = session === 'AM' ? CONFIG.amStart : CONFIG.pmStart;
      const lateAfter = session === 'AM' ? CONFIG.amLateAfter : CONFIG.pmLateAfter;
      const end = session === 'AM' ? CONFIG.amEnd : CONFIG.pmEnd;

      // Decide outcome for this learner on this day
      let outcome: LearnerDayOutcome;
      if (chance(CONFIG.pLeave)) {
        outcome = { status: 'leave', firstPingUtc: null, lastPingUtc: null };
      } else if (chance(CONFIG.pAbsent)) {
        outcome = { status: 'absent', firstPingUtc: null, lastPingUtc: null };
      } else {
        const isLate = chance(CONFIG.pLate);
        // First-ping local time
        const startUtc = combineLocalDateAndTime(dateStr, start, CONFIG.timezone);
        const lateAfterUtc = combineLocalDateAndTime(dateStr, lateAfter, CONFIG.timezone);
        const endUtc = combineLocalDateAndTime(dateStr, end, CONFIG.timezone);

        let firstMs: number;
        if (isLate) {
          // 0-30 min after late_after
          firstMs = lateAfterUtc.getTime() + randInt(0, 30 * 60 * 1000);
        } else {
          // between start and (late_after - 1min)
          firstMs = startUtc.getTime() + randInt(0, Math.max(0, lateAfterUtc.getTime() - startUtc.getTime() - 60_000));
        }

        // Cap so we don't cross end time
        firstMs = Math.min(firstMs, endUtc.getTime() - 60_000);

        outcome = {
          status: isLate ? 'late' : 'early',
          firstPingUtc: new Date(firstMs),
          lastPingUtc: null, // computed below as we generate pings
        };

        // Generate pings every ~5 min from first ping until end
        const roomId = roomIds[userId % roomIds.length];
        const battery = randInt(40, 100);
        const jitterMin = 1;
        let cursor = firstMs;
        let batteryNow = battery;
        while (cursor < endUtc.getTime()) {
          // Occasional gap (learner steps out)
          const gapMinutes = CONFIG.pingIntervalMinutes + randInt(-jitterMin, jitterMin);
          cursor += gapMinutes * 60 * 1000;
          if (cursor >= endUtc.getTime()) break;
          const px = 1 + rng() * 8; // 1..9 meters
          const py = 1 + rng() * 8;
          batteryNow = Math.max(20, batteryNow - (chance(0.15) ? 1 : 0));
          presenceRows.push([userId, roomId, new Date(cursor), Number(px.toFixed(2)), Number(py.toFixed(2)), batteryNow]);
          outcome.lastPingUtc = new Date(cursor);
        }
      }

      // For today: skip ATTENDANCE_HISTORY row (nightly rollup writes yesterday's; today is live)
      if (!isToday) {
        historyRows.push([userId, dateStr, outcome.status]);
      }
    }
  }

  // Bulk insert presence logs (batched)
  if (presenceRows.length > 0) {
    const BATCH = 500;
    for (let i = 0; i < presenceRows.length; i += BATCH) {
      const chunk = presenceRows.slice(i, i + BATCH);
      const placeholders = chunk.map(() => '(?, ?, ?, ?, ?, ?)').join(', ');
      const flat = chunk.flat();
      await pool.query(
        `INSERT INTO \`PRESENCE_LOG\`
           (\`id_user\`, \`id_room\`, \`timestamp\`, \`position_x\`, \`position_y\`, \`battery_level\`)
         VALUES ${placeholders}`,
        flat,
      );
    }
  }

  // Bulk insert attendance history
  if (historyRows.length > 0) {
    const BATCH = 500;
    for (let i = 0; i < historyRows.length; i += BATCH) {
      const chunk = historyRows.slice(i, i + BATCH);
      const placeholders = chunk.map(() => '(?, ?, ?)').join(', ');
      const flat = chunk.flat();
      await pool.query(
        `INSERT INTO \`ATTENDANCE_HISTORY\` (\`id_user\`, \`date\`, \`status\`) VALUES ${placeholders}`,
        flat,
      );
    }
  }

  logger.info(
    { presence_rows: presenceRows.length, history_rows: historyRows.length },
    'PRESENCE_LOG + ATTENDANCE_HISTORY seeded',
  );
}

async function truncateAll(): Promise<void> {
  logger.info('Truncating mutable tables');
  await pool.query('SET FOREIGN_KEY_CHECKS = 0');
  const tables = ['REFRESH_TOKEN', 'ATTENDANCE_HISTORY', 'PRESENCE_LOG', 'DEVICE', 'ROOM', 'USER'];
  for (const t of tables) {
    await pool.query(`TRUNCATE TABLE \`${t}\``);
  }
  await pool.query('SET FOREIGN_KEY_CHECKS = 1');
}

async function summary(): Promise<void> {
  const rows = async (q: string) => {
    const [r] = await pool.query<({ c: number } & RowDataPacket)[]>(q);
    return r[0].c;
  };
  const counts = {
    users: await rows('SELECT COUNT(*) AS c FROM `USER`'),
    admins: await rows(`SELECT COUNT(*) AS c FROM \`USER\` WHERE role = 'admin'`),
    learners: await rows(`SELECT COUNT(*) AS c FROM \`USER\` WHERE role = 'learner'`),
    rooms: await rows('SELECT COUNT(*) AS c FROM `ROOM`'),
    devices: await rows('SELECT COUNT(*) AS c FROM `DEVICE`'),
    presence: await rows('SELECT COUNT(*) AS c FROM `PRESENCE_LOG`'),
    history: await rows('SELECT COUNT(*) AS c FROM `ATTENDANCE_HISTORY`'),
  };
  logger.info(counts, 'Seed summary');
}

async function main() {
  if (!isGuarded()) {
    logger.error('seedDev refused: set AEGIS_SEED_DEV=1 or pass --force to run');
    process.exit(2);
  }

  logger.info({ config: CONFIG }, 'Starting dev fixtures');
  await truncateAll();

  const { learnerIds, learnerSessions } = await seedUsers();
  const { roomIds } = await seedRoomsAndDevices();
  await seedPresenceAndHistory(learnerIds, learnerSessions, roomIds);

  await summary();
  logger.info(
    { username: 'admin', password: CONFIG.devPassword },
    'Dev fixtures complete. Admin login below.',
  );
  await pool.end();
}

main().catch(async (err) => {
  logger.error({ err }, 'Dev seed failed');
  await pool.end();
  process.exit(1);
});
