import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

describe('config', () => {
  const originalEnv = { ...process.env };

  beforeEach(() => {
    process.env = { ...originalEnv };
    vi.resetModules();
  });

  afterEach(() => {
    process.env = originalEnv;
    vi.resetModules();
  });

  it('throws when JWT_SECRET is missing', async () => {
    delete process.env.JWT_SECRET;
    await expect(import('../../src/lib/config.js')).rejects.toThrow(/JWT_SECRET/);
  });

  it('loads all values when env is complete', async () => {
    process.env.JWT_SECRET = 'x'.repeat(32);
    process.env.DB_HOST = 'localhost';
    process.env.DB_PORT = '3306';
    process.env.DB_USER = 'u';
    process.env.DB_PASSWORD = 'p';
    process.env.DB_NAME = 'AEGIS';
    process.env.PORT = '3000';
    process.env.LOG_LEVEL = 'info';
    const mod = await import('../../src/lib/config.js');
    expect(mod.config.jwtSecret.length).toBeGreaterThanOrEqual(32);
    expect(mod.config.db.name).toBe('AEGIS');
    expect(mod.config.port).toBe(3000);
  });
});
