import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

vi.mock('../../src/db/queries/reportsQueries.js', () => ({
  attendanceRecordsInRange: vi.fn(),
  attendanceAggregatesInRange: vi.fn(),
  firstLastPingsByLocalDay: vi.fn(),
}));
vi.mock('../../src/services/configService.js', () => ({
  getSessionConfigs: vi.fn(),
  getSystemConfig: vi.fn(),
}));

const load = async () => {
  const svc = await import('../../src/services/reportsService.js');
  const rq = await import('../../src/db/queries/reportsQueries.js');
  const cfg = await import('../../src/services/configService.js');
  return { svc, rq, cfg };
};

beforeEach(() => vi.clearAllMocks());

describe('getAttendanceReport', () => {
  it('builds range, summary, per_learner, and records', async () => {
    const { svc, rq, cfg } = await load();
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'UTC' });
    (rq.attendanceRecordsInRange as any).mockResolvedValue([
      { id_user: 1, date: '2026-06-01', status: 'early', session: 'AM', name: 'Ada Lovelace' },
      { id_user: 1, date: '2026-06-02', status: 'late', session: 'AM', name: 'Ada Lovelace' },
      { id_user: 2, date: '2026-06-01', status: 'absent', session: 'PM', name: 'grace' },
      { id_user: 2, date: '2026-06-02', status: 'leave', session: 'PM', name: 'grace' },
    ]);
    (rq.attendanceAggregatesInRange as any).mockResolvedValue({
      perLearner: [
        { id_user: 1, session: 'AM', name: 'Ada Lovelace', present: 2, late: 1, absent: 0 },
        { id_user: 2, session: 'PM', name: 'grace', present: 0, late: 0, absent: 1 },
      ],
      daysWithSessions: 2,
    });
    (rq.firstLastPingsByLocalDay as any).mockResolvedValue(new Map([
      ['2026-06-01|1', { first: new Date('2026-06-01T08:00:00Z'), last: new Date('2026-06-01T12:00:00Z') }],
      ['2026-06-02|1', { first: new Date('2026-06-02T08:20:00Z'), last: new Date('2026-06-02T12:00:00Z') }],
    ]));

    const report = await svc.getAttendanceReport({ from: '2026-06-01', to: '2026-06-30' });

    expect(report.range).toEqual({ from: '2026-06-01', to: '2026-06-30', days_with_sessions: 2 });
    // totals: present 2, absent 1 → 2/3 = 0.6667
    expect(report.summary).toEqual({ learners: 2, attendance_rate: 0.6667, total_late: 1, total_absent: 1 });
    expect(report.per_learner).toEqual([
      { user_id: 1, name: 'Ada Lovelace', session: 'AM', present: 2, late: 1, absent: 0, attendance_rate: 1 },
      { user_id: 2, name: 'grace', session: 'PM', present: 0, late: 0, absent: 1, attendance_rate: 0 },
    ]);
    expect(report.records).toEqual([
      { date: '2026-06-01', user_id: 1, name: 'Ada Lovelace', session: 'AM', status: 'early', clocked_in_at: '2026-06-01T08:00:00.000Z', clocked_out_at: '2026-06-01T12:00:00.000Z' },
      { date: '2026-06-02', user_id: 1, name: 'Ada Lovelace', session: 'AM', status: 'late', clocked_in_at: '2026-06-02T08:20:00.000Z', clocked_out_at: '2026-06-02T12:00:00.000Z' },
      { date: '2026-06-01', user_id: 2, name: 'grace', session: 'PM', status: 'absent', clocked_in_at: null, clocked_out_at: null },
      { date: '2026-06-02', user_id: 2, name: 'grace', session: 'PM', status: 'leave', clocked_in_at: null, clocked_out_at: null },
    ]);
  });

  it('returns an empty report when no attendance rows exist', async () => {
    const { svc, rq, cfg } = await load();
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'UTC' });
    (rq.attendanceRecordsInRange as any).mockResolvedValue([]);
    (rq.attendanceAggregatesInRange as any).mockResolvedValue({ perLearner: [], daysWithSessions: 0 });
    (rq.firstLastPingsByLocalDay as any).mockResolvedValue(new Map());

    const report = await svc.getAttendanceReport({ from: '2026-06-01', to: '2026-06-30' });
    expect(report.summary).toEqual({ learners: 0, attendance_rate: 0, total_late: 0, total_absent: 0 });
    expect(report.per_learner).toEqual([]);
    expect(report.records).toEqual([]);
  });

  it('rounds attendance_rate to 4 decimals', async () => {
    const { svc, rq, cfg } = await load();
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'UTC' });
    (rq.attendanceRecordsInRange as any).mockResolvedValue([]);
    (rq.attendanceAggregatesInRange as any).mockResolvedValue({
      perLearner: [{ id_user: 1, session: 'AM', name: 'a', present: 1, late: 0, absent: 2 }],
      daysWithSessions: 3,
    });
    (rq.firstLastPingsByLocalDay as any).mockResolvedValue(new Map());

    const report = await svc.getAttendanceReport({ from: '2026-06-01', to: '2026-06-30' });
    expect(report.per_learner[0].attendance_rate).toBe(0.3333);
    expect(report.summary.attendance_rate).toBe(0.3333);
  });

  it('passes filters through to the queries', async () => {
    const { svc, rq, cfg } = await load();
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'UTC' });
    (rq.attendanceRecordsInRange as any).mockResolvedValue([]);
    (rq.attendanceAggregatesInRange as any).mockResolvedValue({ perLearner: [], daysWithSessions: 0 });
    (rq.firstLastPingsByLocalDay as any).mockResolvedValue(new Map());

    await svc.getAttendanceReport({ from: '2026-06-01', to: '2026-06-30', session: 'AM', userId: 3 });
    expect(rq.attendanceRecordsInRange).toHaveBeenCalledWith('2026-06-01', '2026-06-30', { session: 'AM', userId: 3 });
    expect(rq.attendanceAggregatesInRange).toHaveBeenCalledWith('2026-06-01', '2026-06-30', { session: 'AM', userId: 3 });
  });
});

describe('reportRecordsToCsv', () => {
  it('produces RFC-4180 output with CRLF, quoting, and empty nulls', async () => {
    const { svc } = await load();
    const csv = svc.reportRecordsToCsv([
      { date: '2026-06-01', user_id: 1, name: 'Plain Name', session: 'AM', status: 'early', clocked_in_at: '2026-06-01T08:00:00.000Z', clocked_out_at: null },
      { date: '2026-06-02', user_id: 2, name: 'Comma, Name', session: 'PM', status: 'absent', clocked_in_at: null, clocked_out_at: null },
      { date: '2026-06-03', user_id: 3, name: 'Quote "Q" Name', session: 'AM', status: 'late', clocked_in_at: null, clocked_out_at: null },
      { date: '2026-06-04', user_id: 4, name: 'New\nLine', session: 'PM', status: 'leave', clocked_in_at: null, clocked_out_at: null },
    ]);
    expect(csv).toBe(
      'date,user_id,name,session,status,clocked_in_at,clocked_out_at\r\n' +
      '2026-06-01,1,Plain Name,AM,early,2026-06-01T08:00:00.000Z,\r\n' +
      '2026-06-02,2,"Comma, Name",PM,absent,,\r\n' +
      '2026-06-03,3,"Quote ""Q"" Name",AM,late,,\r\n' +
      '2026-06-04,4,"New\nLine",PM,leave,,\r\n',
    );
  });

  it('returns only the header row for empty records', async () => {
    const { svc } = await load();
    expect(svc.reportRecordsToCsv([])).toBe('date,user_id,name,session,status,clocked_in_at,clocked_out_at\r\n');
  });
});
