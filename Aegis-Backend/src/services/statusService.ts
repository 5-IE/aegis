import { getSessionConfigs, getSystemConfig } from './configService.js';

export type TodayStatus =
  | 'Not Checked In'
  | 'Running Late'
  | 'Checked In'
  | 'Checked Out'
  | 'Not Checked Out'
  | 'Off';

export type HistoricalStatus = 'early' | 'late' | 'leave' | 'absent';

function parts(date: Date, tz: string): { y: number; m: number; d: number; h: number; mi: number; s: number } {
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

// Return the UTC Date corresponding to <localDate>T<time> in tz.
export function combineLocalDateAndTime(localDate: string, timeHHMMSS: string, tz: string): Date {
  const [y, mo, d] = localDate.split('-').map((x) => Number.parseInt(x, 10));
  const [h, mi, s] = timeHHMMSS.split(':').map((x) => Number.parseInt(x, 10));

  // Iterative search: pick a guess, compute what local components that guess produces,
  // then adjust by the difference. tz offsets are integer minutes so this converges in 2 iterations.
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

export function localDateStr(now: Date, tz: string): string {
  const p = parts(now, tz);
  const mm = String(p.m).padStart(2, '0');
  const dd = String(p.d).padStart(2, '0');
  return `${p.y}-${mm}-${dd}`;
}

export function localDayBoundsUtc(now: Date, tz: string): { startUtc: Date; endUtc: Date } {
  const date = localDateStr(now, tz);
  const startUtc = combineLocalDateAndTime(date, '00:00:00', tz);
  const endUtc = new Date(startUtc.getTime() + 24 * 60 * 60 * 1000);
  return { startUtc, endUtc };
}

export async function computeTodayStatus(
  userSession: 'AM' | 'PM',
  now: Date,
  firstPing: Date | null,
  lastPing: Date | null,
  hasLeave: boolean,
): Promise<TodayStatus> {
  if (hasLeave) return 'Off';

  const [{ AM, PM }, sys] = await Promise.all([getSessionConfigs(), getSystemConfig()]);
  const cfg = userSession === 'AM' ? AM : PM;
  const date = localDateStr(now, sys.timezone);
  const lateAfterUtc = combineLocalDateAndTime(date, cfg.late_after, sys.timezone);
  const endUtc = combineLocalDateAndTime(date, cfg.end_time, sys.timezone);

  if (firstPing) {
    if (now < endUtc) return 'Checked In';
    const staleMs = sys.presence_staleness_minutes * 60_000;
    if (lastPing && now.getTime() - lastPing.getTime() <= staleMs) return 'Not Checked Out';
    return 'Checked Out';
  }
  if (now < lateAfterUtc) return 'Not Checked In';
  if (now < endUtc) return 'Running Late';
  return 'Not Checked In';
}

export function computeHistoricalStatus(
  firstPing: Date | null,
  sessionLateAfterUtc: Date,
  existingLeave: boolean,
): HistoricalStatus {
  if (existingLeave) return 'leave';
  if (!firstPing) return 'absent';
  return firstPing <= sessionLateAfterUtc ? 'early' : 'late';
}
