import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

// Fake connection returned by pool.getConnection() — supports transaction plumbing.
const fakeConn = {
  beginTransaction: vi.fn().mockResolvedValue(undefined),
  commit: vi.fn().mockResolvedValue(undefined),
  rollback: vi.fn().mockResolvedValue(undefined),
  release: vi.fn(),
};

vi.mock('../../src/db/pool.js', () => ({
  pool: {
    getConnection: vi.fn().mockResolvedValue(fakeConn),
  },
}));

vi.mock('../../src/db/queries/userQueries.js', () => ({
  findUserByUsername: vi.fn(),
  findUserById: vi.fn(),
  insertUser: vi.fn(),
}));

vi.mock('../../src/db/queries/refreshTokenQueries.js', () => ({
  insertRefreshToken: vi.fn(),
  findRefreshTokenByHash: vi.fn(),
  revokeRefreshToken: vi.fn(),
  revokeAllRefreshTokensForUser: vi.fn(),
  // Transaction-aware variants used by refresh()
  findRefreshTokenByHashForUpdate: vi.fn(),
  insertRefreshTokenTx: vi.fn(),
  revokeRefreshTokenTx: vi.fn(),
}));

const load = async () => {
  const svc = await import('../../src/services/authService.js');
  const users = await import('../../src/db/queries/userQueries.js');
  const tokens = await import('../../src/db/queries/refreshTokenQueries.js');
  const pw = await import('../../src/services/passwordService.js');
  return { svc, users, tokens, pw };
};

const learner = {
  id_user: 42,
  username: 'alice',
  password: '',
  email: 'a@x',
  role: 'learner' as const,
  first_name: 'Alice',
  last_name: 'Doe',
  session: 'AM' as const,
};

beforeEach(() => {
  vi.clearAllMocks();
  // Re-apply default happy-path behaviour for transaction plumbing after clearAllMocks.
  fakeConn.beginTransaction.mockResolvedValue(undefined);
  fakeConn.commit.mockResolvedValue(undefined);
  fakeConn.rollback.mockResolvedValue(undefined);
});

describe('login', () => {
  it('returns tokens and user on valid credentials', async () => {
    const { svc, users, tokens, pw } = await load();
    const hash = await pw.hashPassword('hunter2');
    (users.findUserByUsername as any).mockResolvedValue({ ...learner, password: hash });
    (tokens.insertRefreshToken as any).mockResolvedValue(1);

    const result = await svc.login('alice', 'hunter2');
    expect(result.accessToken).toBeTruthy();
    expect(result.refreshToken).toBeTruthy();
    expect(result.expiresIn).toBe(900);
    expect(result.user.id).toBe(42);
    expect(result.user.role).toBe('learner');
    expect(tokens.insertRefreshToken).toHaveBeenCalledOnce();
  });

  it('sets requireDeviceRegistration for a learner with no device key', async () => {
    const { svc, users, tokens, pw } = await load();
    const hash = await pw.hashPassword('hunter2');
    (users.findUserByUsername as any).mockResolvedValue({ ...learner, password: hash, device_public_key: null });
    (tokens.insertRefreshToken as any).mockResolvedValue(1);

    const result = await svc.login('alice', 'hunter2');
    expect(result.requireDeviceRegistration).toBe(true);
  });

  it('clears requireDeviceRegistration for a learner with a registered device', async () => {
    const { svc, users, tokens, pw } = await load();
    const hash = await pw.hashPassword('hunter2');
    (users.findUserByUsername as any).mockResolvedValue({ ...learner, password: hash, device_public_key: 'AAAA' });
    (tokens.insertRefreshToken as any).mockResolvedValue(1);

    const result = await svc.login('alice', 'hunter2');
    expect(result.requireDeviceRegistration).toBe(false);
  });

  it('never requires device registration for an admin', async () => {
    const { svc, users, tokens, pw } = await load();
    const hash = await pw.hashPassword('hunter2');
    (users.findUserByUsername as any).mockResolvedValue({
      ...learner, role: 'admin', password: hash, device_public_key: null,
    });
    (tokens.insertRefreshToken as any).mockResolvedValue(1);

    const result = await svc.login('alice', 'hunter2');
    expect(result.requireDeviceRegistration).toBe(false);
  });

  it('throws invalid_credentials for unknown user', async () => {
    const { svc, users } = await load();
    (users.findUserByUsername as any).mockResolvedValue(null);
    await expect(svc.login('nobody', 'x')).rejects.toMatchObject({ code: 'invalid_credentials' });
  });

  it('throws invalid_credentials for wrong password', async () => {
    const { svc, users, pw } = await load();
    const hash = await pw.hashPassword('hunter2');
    (users.findUserByUsername as any).mockResolvedValue({ ...learner, password: hash });
    await expect(svc.login('alice', 'wrong')).rejects.toMatchObject({ code: 'invalid_credentials' });
  });
});

describe('refresh', () => {
  it('rotates a valid refresh token', async () => {
    const { svc, tokens, users } = await load();
    const tokenSvc = await import('../../src/services/tokenService.js');
    const gen = tokenSvc.generateRefreshToken();
    const tokenRow = {
      id_token: 5,
      id_user: 42,
      token_hash: gen.hash,
      expires_at: new Date(Date.now() + 1000_000),
      revoked_at: null,
      replaced_by_id: null,
      created_at: new Date(),
    };
    // Pre-check (pool query) returns the valid row
    (tokens.findRefreshTokenByHash as any).mockResolvedValue(tokenRow);
    // SELECT FOR UPDATE inside the transaction also returns it
    (tokens.findRefreshTokenByHashForUpdate as any).mockResolvedValue(tokenRow);
    (users.findUserById as any).mockResolvedValue(learner);
    (tokens.insertRefreshTokenTx as any).mockResolvedValue(6);

    const result = await svc.refresh(gen.token);
    expect(result.accessToken).toBeTruthy();
    expect(result.refreshToken).not.toBe(gen.token);
    expect(tokens.revokeRefreshTokenTx).toHaveBeenCalledWith(fakeConn, 5, 6);
  });

  it('cascade-revokes when a revoked token is reused', async () => {
    const { svc, tokens } = await load();
    const tokenSvc = await import('../../src/services/tokenService.js');
    const gen = tokenSvc.generateRefreshToken();
    (tokens.findRefreshTokenByHash as any).mockResolvedValue({
      id_token: 5,
      id_user: 42,
      token_hash: gen.hash,
      expires_at: new Date(Date.now() + 1000_000),
      revoked_at: new Date(),
      replaced_by_id: 6,
      created_at: new Date(),
    });
    await expect(svc.refresh(gen.token)).rejects.toMatchObject({ code: 'invalid_grant' });
    expect(tokens.revokeAllRefreshTokensForUser).toHaveBeenCalledWith(42);
  });

  it('rejects unknown refresh token', async () => {
    const { svc, tokens } = await load();
    (tokens.findRefreshTokenByHash as any).mockResolvedValue(null);
    await expect(svc.refresh('bogus')).rejects.toMatchObject({ code: 'invalid_grant' });
  });

  it('rejects expired refresh token', async () => {
    const { svc, tokens } = await load();
    const tokenSvc = await import('../../src/services/tokenService.js');
    const gen = tokenSvc.generateRefreshToken();
    const expiredRow = {
      id_token: 5,
      id_user: 42,
      token_hash: gen.hash,
      expires_at: new Date(Date.now() - 1000),
      revoked_at: null,
      replaced_by_id: null,
      created_at: new Date(),
    };
    // Pre-check returns non-revoked so we enter the transaction path
    (tokens.findRefreshTokenByHash as any).mockResolvedValue(expiredRow);
    // FOR UPDATE inside transaction also returns the expired row
    (tokens.findRefreshTokenByHashForUpdate as any).mockResolvedValue(expiredRow);
    await expect(svc.refresh(gen.token)).rejects.toMatchObject({ code: 'invalid_grant' });
  });
});

describe('logout', () => {
  it('revokes an existing token', async () => {
    const { svc, tokens } = await load();
    (tokens.findRefreshTokenByHash as any).mockResolvedValue({
      id_token: 5, id_user: 42, token_hash: 'x', expires_at: new Date(Date.now() + 1000),
      revoked_at: null, replaced_by_id: null, created_at: new Date(),
    });
    await svc.logout('sometoken');
    expect(tokens.revokeRefreshToken).toHaveBeenCalledWith(5, null);
  });

  it('is idempotent for unknown token', async () => {
    const { svc, tokens } = await load();
    (tokens.findRefreshTokenByHash as any).mockResolvedValue(null);
    await expect(svc.logout('bogus')).resolves.toBeUndefined();
    expect(tokens.revokeRefreshToken).not.toHaveBeenCalled();
  });
});
