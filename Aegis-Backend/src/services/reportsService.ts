import {
  attendanceRecordsInRange,
  attendanceAggregatesInRange,
  firstLastPingsByLocalDay,
  DayWindow,
} from '../db/queries/reportsQueries.js';
import { getSystemConfig } from './configService.js';
import { combineLocalDateAndTime } from './statusService.js';

// Status mapping (canonical ATTENDANCE_HISTORY statuses, see statusService.HistoricalStatus):
//   present = 'early' + 'late'  (the learner showed up)
//   late    = 'late'
//   absent  = 'absent'
//   'leave' is an excused day: it counts as neither present nor absent and is
//   excluded from attendance_rate entirely (it still appears in `records`).
// attendance_rate = present / (present + absent), i.e. share of unexcused days
// the learner attended. When present + absent === 0 the rate is 0.
// Rates are rounded to 4 decimals.

export interface AttendanceReport {
  range: { from: string; to: string; days_with_sessions: number };
  summary: { learners: number; attendance_rate: number; total_late: number; total_absent: number };
  per_learner: Array<{
    user_id: number;
    name: string;
    session: 'AM' | 'PM';
    present: number;
    late: number;
    absent: number;
    attendance_rate: number;
  }>;
  records: Array<{
    date: string;
    user_id: number;
    name: string;
    session: 'AM' | 'PM';
    status: 'early' | 'late' | 'leave' | 'absent';
    clocked_in_at: string | null;
    clocked_out_at: string | null;
  }>;
}

function rate(present: number, absent: number): number {
  const denom = present + absent;
  if (denom === 0) return 0;
  return Math.round((present / denom) * 10000) / 10000;
}

export async function getAttendanceReport(input: {
  from: string;
  to: string;
  session?: 'AM' | 'PM';
  userId?: number;
}): Promise<AttendanceReport> {
  const filter = { session: input.session, userId: input.userId };
  const [rows, { perLearner, daysWithSessions }, sys] = await Promise.all([
    attendanceRecordsInRange(input.from, input.to, filter),
    attendanceAggregatesInRange(input.from, input.to, filter),
    getSystemConfig(),
  ]);

  // Resolve clock-in/out per (date, user) from PRESENCE_LOG using the same
  // local-day windows the rollup uses.
  const dates = [...new Set(rows.map((r) => r.date))];
  const userIds = [...new Set(rows.map((r) => r.id_user))];
  const windows: DayWindow[] = dates.map((date) => {
    const startUtc = combineLocalDateAndTime(date, '00:00:00', sys.timezone);
    const endUtc = new Date(startUtc.getTime() + 24 * 60 * 60 * 1000);
    return { date, startUtc, endUtc };
  });
  const pings = await firstLastPingsByLocalDay(windows, userIds);

  const records = rows.map((r) => {
    const p = pings.get(`${r.date}|${r.id_user}`);
    return {
      date: r.date,
      user_id: r.id_user,
      name: r.name,
      session: r.session,
      status: r.status,
      clocked_in_at: p ? p.first.toISOString() : null,
      clocked_out_at: p ? p.last.toISOString() : null,
    };
  });

  const per_learner = perLearner.map((l) => ({
    user_id: l.id_user,
    name: l.name,
    session: l.session,
    present: l.present,
    late: l.late,
    absent: l.absent,
    attendance_rate: rate(l.present, l.absent),
  }));

  const totalPresent = per_learner.reduce((acc, l) => acc + l.present, 0);
  const totalLate = per_learner.reduce((acc, l) => acc + l.late, 0);
  const totalAbsent = per_learner.reduce((acc, l) => acc + l.absent, 0);

  return {
    range: { from: input.from, to: input.to, days_with_sessions: daysWithSessions },
    summary: {
      learners: per_learner.length,
      attendance_rate: rate(totalPresent, totalAbsent),
      total_late: totalLate,
      total_absent: totalAbsent,
    },
    per_learner,
    records,
  };
}

// RFC 4180: quote fields containing comma, quote, CR, or LF; double embedded quotes.
function csvField(value: string | number | null): string {
  if (value === null) return '';
  const s = String(value);
  if (/[",\r\n]/.test(s)) {
    return `"${s.replace(/"/g, '""')}"`;
  }
  return s;
}

export function reportRecordsToCsv(records: AttendanceReport['records']): string {
  const lines = ['date,user_id,name,session,status,clocked_in_at,clocked_out_at'];
  for (const r of records) {
    lines.push(
      [
        csvField(r.date),
        csvField(r.user_id),
        csvField(r.name),
        csvField(r.session),
        csvField(r.status),
        csvField(r.clocked_in_at),
        csvField(r.clocked_out_at),
      ].join(','),
    );
  }
  return lines.join('\r\n') + '\r\n';
}
