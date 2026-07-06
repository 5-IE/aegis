import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

vi.mock('../../src/db/queries/userQueries.js', () => ({
  findUserByUsername: vi.fn(),
  findUserByUsernameAnyState: vi.fn(),
  findUserById: vi.fn(),
  findUserByIdAnyState: vi.fn(),
  findUserByEmailActive: vi.fn(),
  insertUser: vi.fn(),
  listLearners: vi.fn(),
  listLearnerIds: vi.fn(),
  countLearners: vi.fn(),
  listUsers: vi.fn(),
  updateUserFields: vi.fn(),
  updateUserPassword: vi.fn(),
  softDeleteUser: vi.fn(),
  reactivateUser: vi.fn(),
  countActiveAdmins: vi.fn(),
}));

vi.mock('../../src/db/queries/refreshTokenQueries.js', () => ({
  insertRefreshToken: vi.fn(),
  findRefreshTokenByHash: vi.fn(),
  revokeRefreshToken: vi.fn(),
  revokeAllRefreshTokensForUser: vi.fn(),
  findRefreshTokenByHashForUpdate: vi.fn(),
  insertRefreshTokenTx: vi.fn(),
  revokeRefreshTokenTx: vi.fn(),
}));

const load = async () => {
  const svc = await import('../../src/services/userService.js');
  const uq = await import('../../src/db/queries/userQueries.js');
  const rt = await import('../../src/db/queries/refreshTokenQueries.js');
  return { svc, uq, rt };
};

const learnerRow = {
  id_user: 42,
  username: 'alice',
  password: 'HASH',
  email: 'alice@example.com',
  role: 'learner' as const,
  first_name: 'Alice',
  last_name: 'Doe',
  session: 'AM' as const,
  is_active: true,
  created_at: new Date('2026-01-15T00:00:00Z'),
};

const adminRow = {
  ...learnerRow,
  id_user: 1,
  username: 'admin',
  role: 'admin' as const,
  first_name: null,
  last_name: null,
  email: 'admin@example.com',
};

beforeEach(() => vi.clearAllMocks());

describe('toPublicUser', () => {
  it('strips password and formats created_at as ISO string', async () => {
    const { svc } = await load();
    const pub = svc.toPublicUser(learnerRow);
    expect(pub).toEqual({
      id: 42,
      username: 'alice',
      email: 'alice@example.com',
      role: 'learner',
      session: 'AM',
      first_name: 'Alice',
      last_name: 'Doe',
      is_active: true,
      created_at: '2026-01-15T00:00:00.000Z',
    });
    expect((pub as any).password).toBeUndefined();
  });
});

describe('listUsersService', () => {
  it('returns paged list with total', async () => {
    const { svc, uq } = await load();
    (uq.listUsers as any).mockResolvedValue({ list: [learnerRow, adminRow], total: 2 });
    const r = await svc.listUsersService({}, 1, 20);
    expect(r.total).toBe(2);
    expect(r.list).toHaveLength(2);
    expect(r.list[0].id).toBe(42);
    expect(r.page).toBe(1);
    expect(r.per_page).toBe(20);
  });
});

describe('getUserService', () => {
  it('returns public user for existing id', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue(learnerRow);
    const pub = await svc.getUserService(42);
    expect(pub.id).toBe(42);
  });

  it('throws not_found when missing', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue(null);
    await expect(svc.getUserService(999)).rejects.toMatchObject({ code: 'not_found' });
  });
});

describe('createUserService', () => {
  it('creates a learner and returns public user', async () => {
    const { svc, uq } = await load();
    (uq.findUserByUsernameAnyState as any).mockResolvedValue(null);
    (uq.findUserByEmailActive as any).mockResolvedValue(null);
    (uq.insertUser as any).mockResolvedValue(42);
    (uq.findUserByIdAnyState as any).mockResolvedValue(learnerRow);

    const pub = await svc.createUserService({
      username: 'alice',
      password: 'hunter2',
      email: 'alice@example.com',
      role: 'learner',
      session: 'AM',
      first_name: 'Alice',
      last_name: 'Doe',
    });
    expect(pub.id).toBe(42);
    expect(uq.insertUser).toHaveBeenCalledOnce();
  });

  it('rejects when session missing for learner', async () => {
    const { svc } = await load();
    await expect(
      svc.createUserService({
        username: 'x',
        password: 'p',
        email: 'x@x',
        role: 'learner',
      } as any),
    ).rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('accepts admin without session', async () => {
    const { svc, uq } = await load();
    (uq.findUserByUsernameAnyState as any).mockResolvedValue(null);
    (uq.findUserByEmailActive as any).mockResolvedValue(null);
    (uq.insertUser as any).mockResolvedValue(1);
    (uq.findUserByIdAnyState as any).mockResolvedValue(adminRow);

    const pub = await svc.createUserService({
      username: 'admin',
      password: 'hunter2',
      email: 'admin@example.com',
      role: 'admin',
    });
    expect(pub.role).toBe('admin');
  });

  it('throws conflict on duplicate username', async () => {
    const { svc, uq } = await load();
    (uq.findUserByUsernameAnyState as any).mockResolvedValue(learnerRow);
    await expect(
      svc.createUserService({
        username: 'alice',
        password: 'p',
        email: 'other@example.com',
        role: 'learner',
        session: 'AM',
      }),
    ).rejects.toMatchObject({ code: 'conflict' });
  });

  it('throws conflict on duplicate active email', async () => {
    const { svc, uq } = await load();
    (uq.findUserByUsernameAnyState as any).mockResolvedValue(null);
    (uq.findUserByEmailActive as any).mockResolvedValue(learnerRow);
    await expect(
      svc.createUserService({
        username: 'newuser',
        password: 'p',
        email: 'alice@example.com',
        role: 'learner',
        session: 'AM',
      }),
    ).rejects.toMatchObject({ code: 'conflict' });
  });
});

describe('updateUserService', () => {
  it('updates first_name and returns fresh public user', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any)
      .mockResolvedValueOnce(learnerRow)
      .mockResolvedValueOnce({ ...learnerRow, first_name: 'Alicia' });
    const pub = await svc.updateUserService(42, { first_name: 'Alicia' });
    expect(pub.first_name).toBe('Alicia');
    expect(uq.updateUserFields).toHaveBeenCalledWith(42, { first_name: 'Alicia' });
  });

  it('throws not_found when user missing', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue(null);
    await expect(svc.updateUserService(999, { first_name: 'X' })).rejects.toMatchObject({ code: 'not_found' });
  });

  it('throws conflict when new email taken by another active user', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue(learnerRow);
    (uq.findUserByEmailActive as any).mockResolvedValue({ ...learnerRow, id_user: 99 });
    await expect(svc.updateUserService(42, { email: 'taken@example.com' })).rejects.toMatchObject({ code: 'conflict' });
  });

  it('allows updating email to the same user own address (idempotent)', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any)
      .mockResolvedValueOnce(learnerRow)
      .mockResolvedValueOnce(learnerRow);
    (uq.findUserByEmailActive as any).mockResolvedValue(learnerRow);
    const pub = await svc.updateUserService(42, { email: 'alice@example.com' });
    expect(pub.email).toBe('alice@example.com');
  });

  it('rejects role=learner update without session when learner has no existing session', async () => {
    const { svc, uq } = await load();
    // hypothetical existing admin being demoted with no session in patch
    // admin's existing session field is 'AM' (DB default), so it IS present; test the intended guard
    // Only reject when both are missing. Here we simulate by patching to a hypothetical no-session row.
    const noSession = { ...adminRow, session: undefined as any };
    (uq.findUserByIdAnyState as any).mockResolvedValueOnce(noSession);
    await expect(svc.updateUserService(1, { role: 'learner' })).rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('throws invalid_request on empty patch', async () => {
    const { svc } = await load();
    await expect(svc.updateUserService(42, {})).rejects.toMatchObject({ code: 'invalid_request' });
  });
});

describe('resetPasswordService', () => {
  it('hashes, updates, and revokes refresh tokens', async () => {
    const { svc, uq, rt } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue(learnerRow);
    await svc.resetPasswordService(42, 'newpassword');
    expect(uq.updateUserPassword).toHaveBeenCalledWith(42, expect.any(String));
    expect(rt.revokeAllRefreshTokensForUser).toHaveBeenCalledWith(42);
  });

  it('throws not_found when user missing', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue(null);
    await expect(svc.resetPasswordService(999, 'p')).rejects.toMatchObject({ code: 'not_found' });
  });
});

describe('deleteUserService', () => {
  it('soft-deletes target and revokes refresh tokens', async () => {
    const { svc, uq, rt } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue(learnerRow);
    await svc.deleteUserService(42, 1);
    expect(uq.softDeleteUser).toHaveBeenCalledWith(42);
    expect(rt.revokeAllRefreshTokensForUser).toHaveBeenCalledWith(42);
  });

  it('rejects self-delete', async () => {
    const { svc } = await load();
    await expect(svc.deleteUserService(1, 1)).rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('rejects last-admin delete', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue(adminRow);
    (uq.countActiveAdmins as any).mockResolvedValue(1);
    await expect(svc.deleteUserService(1, 99)).rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('allows deleting an admin when others exist', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue(adminRow);
    (uq.countActiveAdmins as any).mockResolvedValue(2);
    await svc.deleteUserService(1, 99);
    expect(uq.softDeleteUser).toHaveBeenCalledWith(1);
  });

  it('throws not_found when target missing', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue(null);
    await expect(svc.deleteUserService(999, 1)).rejects.toMatchObject({ code: 'not_found' });
  });
});

describe('reactivateUserService', () => {
  it('reactivates existing user', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue({ ...learnerRow, is_active: false });
    await svc.reactivateUserService(42);
    expect(uq.reactivateUser).toHaveBeenCalledWith(42);
  });

  it('throws not_found when user missing', async () => {
    const { svc, uq } = await load();
    (uq.findUserByIdAnyState as any).mockResolvedValue(null);
    await expect(svc.reactivateUserService(999)).rejects.toMatchObject({ code: 'not_found' });
  });
});
