import { AppError } from '../lib/errors.js';
import {
  countByStatus,
  findByUserAndDate,
} from '../db/queries/attendanceHistoryQueries.js';
import {
  firstPingForUserInWindow,
  lastPingForUserInWindow,
  firstAndLastPingBulk,
} from '../db/queries/presenceQueries.js';
import { findUserById, listLearnerIds } from '../db/queries/userQueries.js';
import { getSessionConfigs, getSystemConfig } from './configService.js';
import {
  computeTodayStatus,
  localDayBoundsUtc,
  localDateStr,
  combineLocalDateAndTime,
  TodayStatus,
} from './statusService.js';

export async function getLearnerDashboard(
  userId: number,
  now: Date,
): Promise<{ total_attendance: number; total_late: number; leave_taken: number; today_status: TodayStatus; check_in_at: Date | null }> {
  const user = await findUserById(userId);
  if (!user) throw new AppError('not_found', 'User not found');

  const [counts, sys] = await Promise.all([countByStatus(userId), getSystemConfig()]);
  const total_attendance = counts.early + counts.late;
  const total_late = counts.late;
  const leave_taken = counts.leave;

  const { startUtc, endUtc } = localDayBoundsUtc(now, sys.timezone);
  const [first, last, todayRow] = await Promise.all([
    firstPingForUserInWindow(userId, startUtc, endUtc),
    lastPingForUserInWindow(userId, startUtc, endUtc),
    findByUserAndDate(userId, localDateStr(now, sys.timezone)),
  ]);
  const hasLeave = todayRow?.status === 'leave';
  const today_status = await computeTodayStatus(user.session, now, first, last, hasLeave);
  return { total_attendance, total_late, leave_taken, today_status, check_in_at: first };
}

export async function getAbsenceSummary(
  now: Date,
): Promise<{ present_summary: { on_time: number; late_clock_in: number }; absent_summary: { absent: number; no_clock_in: number } }> {
  const [{ AM, PM }, sys, learnerIds] = await Promise.all([
    getSessionConfigs(),
    getSystemConfig(),
    listLearnerIds(),
  ]);
  const { startUtc, endUtc } = localDayBoundsUtc(now, sys.timezone);
  const pings = await firstAndLastPingBulk(learnerIds, startUtc, endUtc);

  const date = localDateStr(now, sys.timezone);
  const lateAfterUtc = { AM: combineLocalDateAndTime(date, AM.late_after, sys.timezone), PM: combineLocalDateAndTime(date, PM.late_after, sys.timezone) };
  const endTimeUtc = { AM: combineLocalDateAndTime(date, AM.end_time, sys.timezone), PM: combineLocalDateAndTime(date, PM.end_time, sys.timezone) };

  let on_time = 0, late_clock_in = 0, absent = 0, no_clock_in = 0;

  // Fetch every learner and their today attendance row in parallel.
  const learners = await Promise.all(learnerIds.map((id) => findUserById(id)));
  const leaveRows = await Promise.all(learnerIds.map((id) => findByUserAndDate(id, date)));

  for (let i = 0; i < learners.length; i++) {
    const l = learners[i];
    if (!l) continue;
    if (leaveRows[i]?.status === 'leave') { absent++; continue; }
    const p = pings.get(l.id_user);
    const s = l.session;
    if (p) {
      if (p.first <= lateAfterUtc[s]) on_time++;
      else late_clock_in++;
    } else {
      if (now < endTimeUtc[s]) no_clock_in++;
      else absent++;
    }
  }
  return { present_summary: { on_time, late_clock_in }, absent_summary: { absent, no_clock_in } };
}
