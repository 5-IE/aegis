import { AppError } from '../lib/errors.js';
import {
  getAllSessionConfigs,
  updateSessionConfig as dbUpdateSessionConfig,
} from '../db/queries/sessionConfigQueries.js';
import {
  getAllSystemConfig,
  upsertSystemConfig,
} from '../db/queries/systemConfigQueries.js';

export interface SessionConfig {
  session: 'AM' | 'PM';
  start_time: string;
  late_after: string;
  end_time: string;
}

export interface SystemConfig {
  presence_staleness_minutes: number;
  timezone: string;
}

const TTL_MS = 30_000;

let sessionCache: { AM: SessionConfig; PM: SessionConfig } | null = null;
let sessionCachedAt = 0;
let systemCache: SystemConfig | null = null;
let systemCachedAt = 0;

export function invalidateConfigCache(): void {
  sessionCache = null;
  sessionCachedAt = 0;
  systemCache = null;
  systemCachedAt = 0;
}

function timeStrToSeconds(t: string): number {
  const [h, m, s] = t.split(':').map((x) => Number.parseInt(x, 10));
  return h * 3600 + m * 60 + s;
}

function isValidTimezone(tz: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

export async function getSessionConfigs(): Promise<{ AM: SessionConfig; PM: SessionConfig }> {
  const now = Date.now();
  if (sessionCache && now - sessionCachedAt < TTL_MS) return sessionCache;
  const rows = await getAllSessionConfigs();
  const AM = rows.find((r) => r.session === 'AM');
  const PM = rows.find((r) => r.session === 'PM');
  if (!AM || !PM) throw new AppError('internal_error', 'Session config missing rows');
  sessionCache = {
    AM: { session: 'AM', start_time: AM.start_time, late_after: AM.late_after, end_time: AM.end_time },
    PM: { session: 'PM', start_time: PM.start_time, late_after: PM.late_after, end_time: PM.end_time },
  };
  sessionCachedAt = now;
  return sessionCache;
}

export async function getSystemConfig(): Promise<SystemConfig> {
  const now = Date.now();
  if (systemCache && now - systemCachedAt < TTL_MS) return systemCache;
  const rows = await getAllSystemConfig();
  const map = new Map(rows.map((r) => [r.key, r.value] as const));
  const staleness = Number.parseInt(map.get('presence_staleness_minutes') ?? '5', 10);
  const timezone = map.get('timezone') ?? 'UTC';
  systemCache = { presence_staleness_minutes: staleness, timezone };
  systemCachedAt = now;
  return systemCache;
}

export async function updateSessionConfig(
  session: 'AM' | 'PM',
  input: { start_time: string; late_after: string; end_time: string },
): Promise<void> {
  const s = timeStrToSeconds(input.start_time);
  const l = timeStrToSeconds(input.late_after);
  const e = timeStrToSeconds(input.end_time);
  if (!(s < l && l < e)) {
    throw new AppError('invalid_request', 'Require start_time < late_after < end_time');
  }
  await dbUpdateSessionConfig(session, input);
  invalidateConfigCache();
}

export async function updateSystemConfig(patch: {
  presence_staleness_minutes?: number;
  timezone?: string;
}): Promise<void> {
  if (patch.presence_staleness_minutes !== undefined) {
    const v = patch.presence_staleness_minutes;
    if (!Number.isInteger(v) || v < 1 || v > 60) {
      throw new AppError('invalid_request', 'presence_staleness_minutes must be an integer 1..60');
    }
    await upsertSystemConfig('presence_staleness_minutes', String(v));
  }
  if (patch.timezone !== undefined) {
    if (!isValidTimezone(patch.timezone)) {
      throw new AppError('invalid_request', 'Unknown IANA timezone');
    }
    await upsertSystemConfig('timezone', patch.timezone);
  }
  invalidateConfigCache();
}
