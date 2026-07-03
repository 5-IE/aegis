import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

vi.mock('../../src/db/queries/sessionConfigQueries.js', () => ({
  getAllSessionConfigs: vi.fn(),
  getSessionConfig: vi.fn(),
  updateSessionConfig: vi.fn(),
}));

vi.mock('../../src/db/queries/systemConfigQueries.js', () => ({
  getAllSystemConfig: vi.fn(),
  upsertSystemConfig: vi.fn(),
}));

const load = async () => {
  const svc = await import('../../src/services/configService.js');
  const sc = await import('../../src/db/queries/sessionConfigQueries.js');
  const sy = await import('../../src/db/queries/systemConfigQueries.js');
  return { svc, sc, sy };
};

beforeEach(() => vi.clearAllMocks());

describe('getSessionConfigs', () => {
  it('returns AM and PM configs', async () => {
    const { svc, sc } = await load();
    svc.invalidateConfigCache();
    (sc.getAllSessionConfigs as any).mockResolvedValue([
      { session: 'AM', start_time: '08:00:00', late_after: '08:15:00', end_time: '12:00:00', updated_at: new Date() },
      { session: 'PM', start_time: '13:00:00', late_after: '13:15:00', end_time: '17:00:00', updated_at: new Date() },
    ]);
    const r = await svc.getSessionConfigs();
    expect(r.AM.start_time).toBe('08:00:00');
    expect(r.PM.end_time).toBe('17:00:00');
  });
});

describe('getSystemConfig', () => {
  it('parses values by key', async () => {
    const { svc, sy } = await load();
    svc.invalidateConfigCache();
    (sy.getAllSystemConfig as any).mockResolvedValue([
      { key: 'presence_staleness_minutes', value: '7', updated_at: new Date() },
      { key: 'timezone', value: 'Asia/Jakarta', updated_at: new Date() },
    ]);
    const r = await svc.getSystemConfig();
    expect(r.presence_staleness_minutes).toBe(7);
    expect(r.timezone).toBe('Asia/Jakarta');
  });
});

describe('updateSessionConfig', () => {
  it('rejects if start_time >= late_after', async () => {
    const { svc } = await load();
    await expect(svc.updateSessionConfig('AM', { start_time: '08:15:00', late_after: '08:15:00', end_time: '12:00:00' }))
      .rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('rejects if late_after >= end_time', async () => {
    const { svc } = await load();
    await expect(svc.updateSessionConfig('AM', { start_time: '08:00:00', late_after: '12:00:00', end_time: '12:00:00' }))
      .rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('writes and invalidates cache on success', async () => {
    const { svc, sc } = await load();
    await svc.updateSessionConfig('AM', { start_time: '08:00:00', late_after: '08:15:00', end_time: '12:00:00' });
    expect(sc.updateSessionConfig).toHaveBeenCalledWith('AM', {
      start_time: '08:00:00', late_after: '08:15:00', end_time: '12:00:00',
    });
  });
});

describe('updateSystemConfig', () => {
  it('rejects out-of-range presence_staleness_minutes', async () => {
    const { svc } = await load();
    await expect(svc.updateSystemConfig({ presence_staleness_minutes: 0 })).rejects.toMatchObject({ code: 'invalid_request' });
    await expect(svc.updateSystemConfig({ presence_staleness_minutes: 61 })).rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('rejects invalid timezone', async () => {
    const { svc } = await load();
    await expect(svc.updateSystemConfig({ timezone: 'Not/A_Zone' })).rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('writes each present field', async () => {
    const { svc, sy } = await load();
    await svc.updateSystemConfig({ presence_staleness_minutes: 10, timezone: 'Asia/Jakarta' });
    expect(sy.upsertSystemConfig).toHaveBeenCalledWith('presence_staleness_minutes', '10');
    expect(sy.upsertSystemConfig).toHaveBeenCalledWith('timezone', 'Asia/Jakarta');
  });
});
