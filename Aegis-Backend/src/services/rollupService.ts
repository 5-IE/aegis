import { AppError } from '../lib/errors.js';
import { getSessionConfigs, getSystemConfig } from './configService.js';
import { firstPingForUserInWindow } from '../db/queries/presenceQueries.js';
import { findByUserAndDate, upsertAttendanceHistory } from '../db/queries/attendanceHistoryQueries.js';
import { findUserById, listLearnerIds, UserRow } from '../db/queries/userQueries.js';
import { combineLocalDateAndTime } from './statusService.js';

function yesterdayInTz(now: Date, tz: string): string {
  // Subtract 12 hours from `now`, then format the earlier instant in tz.
  // 12h is safely inside "yesterday" regardless of DST direction (max shift is ~1h).
  // For 3am-local cron: 12h earlier is 3pm previous local day — clearly yesterday.
  const earlier = new Date(now.getTime() - 12 * 60 * 60 * 1000);
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: tz,
    year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(earlier);
}

export async function runRollup(input: {
  date?: string;
  userId?: number;
  now?: Date;
}): Promise<{ processed: number; skipped_leave: number }> {
  const now = input.now ?? new Date();
  const [{ AM, PM }, sys] = await Promise.all([getSessionConfigs(), getSystemConfig()]);
  const date = input.date ?? yesterdayInTz(now, sys.timezone);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new AppError('invalid_request', 'date must be YYYY-MM-DD');
  }

  const targets: number[] = input.userId !== undefined ? [input.userId] : await listLearnerIds();
  let processed = 0;
  let skipped_leave = 0;

  const dayStart = combineLocalDateAndTime(date, '00:00:00', sys.timezone);
  const dayEnd = new Date(dayStart.getTime() + 24 * 60 * 60 * 1000);

  for (const userId of targets) {
    const user: UserRow | null = await findUserById(userId);
    if (!user || user.role !== 'learner') continue;

    const existing = await findByUserAndDate(userId, date);
    if (existing?.status === 'leave') {
      skipped_leave++;
      continue;
    }

    const first = await firstPingForUserInWindow(userId, dayStart, dayEnd);
    const cfg = user.session === 'AM' ? AM : PM;
    const lateAfterUtc = combineLocalDateAndTime(date, cfg.late_after, sys.timezone);

    let status: 'early' | 'late' | 'absent';
    if (!first) status = 'absent';
    else if (first <= lateAfterUtc) status = 'early';
    else status = 'late';

    await upsertAttendanceHistory(userId, date, status);
    processed++;
  }

  return { processed, skipped_leave };
}
