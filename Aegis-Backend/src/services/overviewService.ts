import { listLearners, UserRow } from '../db/queries/userQueries.js';
import { firstAndLastPingBulk } from '../db/queries/presenceQueries.js';
import { findByUserAndDate } from '../db/queries/attendanceHistoryQueries.js';
import { getSystemConfig } from './configService.js';
import { computeTodayStatus, localDayBoundsUtc, localDateStr, TodayStatus } from './statusService.js';

function displayName(row: UserRow): string {
  const parts = [row.first_name, row.last_name].filter((x): x is string => !!x);
  const joined = parts.join(' ').trim();
  return joined || row.username;
}

export async function getOverview(
  now: Date,
  filter: { name?: string; session?: 'AM' | 'PM' },
  page: number,
  perPage: number,
): Promise<{
  list: Array<{ name: string; session: 'AM' | 'PM'; clocked_in_at: string | null; clocked_out_at: string | null; status: TodayStatus }>;
  page: number;
  per_page: number;
  total: number;
}> {
  const { list: learners, total } = await listLearners(filter, page, perPage);
  if (learners.length === 0) {
    return { list: [], page, per_page: perPage, total };
  }

  const sys = await getSystemConfig();
  const { startUtc, endUtc } = localDayBoundsUtc(now, sys.timezone);

  const [pings, leaveRows] = await Promise.all([
    firstAndLastPingBulk(learners.map((l) => l.id_user), startUtc, endUtc),
    (async () => {
      const date = localDateStr(now, sys.timezone);
      return Promise.all(learners.map((l) => findByUserAndDate(l.id_user, date)));
    })(),
  ]);

  const list = await Promise.all(
    learners.map(async (l, idx) => {
      const p = pings.get(l.id_user);
      const first = p?.first ?? null;
      const last = p?.last ?? null;
      const hasLeave = leaveRows[idx]?.status === 'leave';
      const status = await computeTodayStatus(l.session, now, first, last, hasLeave);
      return {
        name: displayName(l),
        session: l.session,
        clocked_in_at: first ? first.toISOString() : null,
        clocked_out_at: last ? last.toISOString() : null,
        status,
      };
    }),
  );

  return { list, page, per_page: perPage, total };
}
