import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

vi.mock('../../src/services/configService.js', () => ({
  getSessionConfigs: vi.fn(),
  getSystemConfig: vi.fn(),
}));

const load = async () => {
  const svc = await import('../../src/services/statusService.js');
  const cfg = await import('../../src/services/configService.js');
  return { svc, cfg };
};

const AM = { session: 'AM' as const, start_time: '08:00:00', late_after: '08:15:00', end_time: '12:00:00' };
const PM = { session: 'PM' as const, start_time: '13:00:00', late_after: '13:15:00', end_time: '17:00:00' };

beforeEach(() => vi.clearAllMocks());

describe('localDayBoundsUtc', () => {
  it('produces a 24h window starting at local midnight', async () => {
    const { svc } = await load();
    // 2026-07-03 in Asia/Jakarta = UTC+7, so local midnight is 2026-07-02T17:00:00Z
    const now = new Date('2026-07-03T05:00:00Z'); // 12:00 local
    const { startUtc, endUtc } = svc.localDayBoundsUtc(now, 'Asia/Jakarta');
    expect(startUtc.toISOString()).toBe('2026-07-02T17:00:00.000Z');
    expect(endUtc.toISOString()).toBe('2026-07-03T17:00:00.000Z');
  });
});

describe('localDateStr', () => {
  it('formats the local date', async () => {
    const { svc } = await load();
    expect(svc.localDateStr(new Date('2026-07-03T05:00:00Z'), 'Asia/Jakarta')).toBe('2026-07-03');
  });
});

describe('combineLocalDateAndTime', () => {
  it('yields the UTC instant of a local wall-clock time', async () => {
    const { svc } = await load();
    // 2026-07-03T08:00 local +07:00 = 2026-07-03T01:00Z
    expect(svc.combineLocalDateAndTime('2026-07-03', '08:00:00', 'Asia/Jakarta').toISOString())
      .toBe('2026-07-03T01:00:00.000Z');
  });
});

describe('computeTodayStatus', () => {
  const setup = async (nowIso: string, opts?: Partial<{ session: 'AM' | 'PM'; firstIso: string; lastIso: string; leave: boolean }>) => {
    const { svc, cfg } = await load();
    (cfg.getSessionConfigs as any).mockResolvedValue({ AM, PM });
    (cfg.getSystemConfig as any).mockResolvedValue({ presence_staleness_minutes: 5, timezone: 'Asia/Jakarta' });
    const now = new Date(nowIso);
    const first = opts?.firstIso ? new Date(opts.firstIso) : null;
    const last = opts?.lastIso ? new Date(opts.lastIso) : first;
    return svc.computeTodayStatus(opts?.session ?? 'AM', now, first, last, opts?.leave ?? false);
  };

  it('returns Off on leave', async () => {
    expect(await setup('2026-07-03T05:00:00Z', { leave: true })).toBe('Off');
  });

  it('returns Checked In when pinged and session not ended', async () => {
    // now = 09:00 local, first ping 08:10 local
    expect(await setup('2026-07-03T02:00:00Z', { firstIso: '2026-07-03T01:10:00Z' })).toBe('Checked In');
  });

  it('returns Not Checked Out after end_time with fresh ping', async () => {
    // now = 12:03 local (past 12:00 end), last ping 12:00 local (3 min ago, within 5 min staleness)
    expect(await setup('2026-07-03T05:03:00Z', { firstIso: '2026-07-03T01:10:00Z', lastIso: '2026-07-03T05:00:00Z' })).toBe('Not Checked Out');
  });

  it('returns Checked Out after end_time when last ping is stale', async () => {
    // now = 12:30 local, last ping 11:00 local (90 min ago)
    expect(await setup('2026-07-03T05:30:00Z', { firstIso: '2026-07-03T01:10:00Z', lastIso: '2026-07-03T04:00:00Z' })).toBe('Checked Out');
  });

  it('returns Not Checked In before late_after with no ping', async () => {
    // now = 08:10 local, no ping, late_after 08:15
    expect(await setup('2026-07-03T01:10:00Z')).toBe('Not Checked In');
  });

  it('returns Running Late between late_after and end_time with no ping', async () => {
    // now = 09:00 local, no ping
    expect(await setup('2026-07-03T02:00:00Z')).toBe('Running Late');
  });

  it('returns Not Checked In after end_time with no ping', async () => {
    // now = 13:00 local, no ping, AM end_time 12:00
    expect(await setup('2026-07-03T06:00:00Z')).toBe('Not Checked In');
  });
});

describe('computeHistoricalStatus', () => {
  it('early when first ping before late_after', async () => {
    const { svc } = await load();
    expect(svc.computeHistoricalStatus(new Date('2026-07-03T01:10:00Z'), new Date('2026-07-03T01:15:00Z'), false)).toBe('early');
  });

  it('late when first ping at/after late_after', async () => {
    const { svc } = await load();
    expect(svc.computeHistoricalStatus(new Date('2026-07-03T01:20:00Z'), new Date('2026-07-03T01:15:00Z'), false)).toBe('late');
  });

  it('leave when existingLeave', async () => {
    const { svc } = await load();
    expect(svc.computeHistoricalStatus(null, new Date('2026-07-03T01:15:00Z'), true)).toBe('leave');
  });

  it('absent when no ping and no leave', async () => {
    const { svc } = await load();
    expect(svc.computeHistoricalStatus(null, new Date('2026-07-03T01:15:00Z'), false)).toBe('absent');
  });

  it('returns early when firstPing equals late_after (boundary)', async () => {
    const { svc } = await load();
    const boundary = new Date('2026-07-03T01:15:00Z');
    expect(svc.computeHistoricalStatus(boundary, boundary, false)).toBe('early');
  });

  it('leave takes priority even when firstPing exists', async () => {
    const { svc } = await load();
    const first = new Date('2026-07-03T01:00:00Z');
    const lateAfter = new Date('2026-07-03T01:15:00Z');
    expect(svc.computeHistoricalStatus(first, lateAfter, true)).toBe('leave');
  });
});
