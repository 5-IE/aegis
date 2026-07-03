import { describe, it, expect, beforeAll } from 'vitest';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

const load = () => import('../../src/services/tokenService.js');

describe('tokenService', () => {
  it('signs and verifies an access token with learner claims', async () => {
    const { signAccessToken, verifyAccessToken } = await load();
    const token = signAccessToken({ sub: 42, role: 'learner', session: 'AM' });
    const claims = verifyAccessToken(token);
    expect(claims.sub).toBe(42);
    expect(claims.role).toBe('learner');
    expect(claims.session).toBe('AM');
    expect(claims.iss).toBe('aegis');
    expect(claims.exp - claims.iat).toBe(900);
  });

  it('signs admin tokens without a session claim', async () => {
    const { signAccessToken, verifyAccessToken } = await load();
    const token = signAccessToken({ sub: 1, role: 'admin' });
    const claims = verifyAccessToken(token);
    expect(claims.role).toBe('admin');
    expect(claims.session).toBeUndefined();
  });

  it('rejects a tampered token', async () => {
    const { signAccessToken, verifyAccessToken } = await load();
    const token = signAccessToken({ sub: 1, role: 'admin' });
    expect(() => verifyAccessToken(token + 'x')).toThrow(/unauthorized/);
  });

  it('generates unique refresh tokens with matching hash', async () => {
    const { generateRefreshToken, hashRefreshToken } = await load();
    const a = generateRefreshToken();
    const b = generateRefreshToken();
    expect(a.token).not.toBe(b.token);
    expect(a.hash).toBe(hashRefreshToken(a.token));
    expect(a.hash).toHaveLength(64);
    expect(a.expiresAt.getTime()).toBeGreaterThan(Date.now());
  });
});
