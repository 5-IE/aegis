import { AppError } from '../lib/errors.js';
import { verifyPassword } from './passwordService.js';
import {
  signAccessToken,
  generateRefreshToken,
  hashRefreshToken,
} from './tokenService.js';
import {
  findUserByUsername,
  findUserById,
  UserRow,
} from '../db/queries/userQueries.js';
import {
  insertRefreshToken,
  findRefreshTokenByHash,
  revokeRefreshToken,
  revokeAllRefreshTokensForUser,
  findRefreshTokenByHashForUpdate,
  insertRefreshTokenTx,
  revokeRefreshTokenTx,
} from '../db/queries/refreshTokenQueries.js';
import { pool } from '../db/pool.js';

const ACCESS_TTL_SECONDS = 900;

export interface PublicUser {
  id: number;
  username: string;
  role: 'admin' | 'learner';
  session: 'AM' | 'PM' | undefined;
  first_name: string | null;
  last_name: string | null;
  email: string;
}

export interface AuthResult {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
}

export interface LoginResult extends AuthResult {
  user: PublicUser;
}

function toPublicUser(row: UserRow): PublicUser {
  return {
    id: row.id_user,
    username: row.username,
    role: row.role,
    session: row.role === 'learner' ? row.session : undefined,
    first_name: row.first_name,
    last_name: row.last_name,
    email: row.email,
  };
}

async function issueTokensFor(user: UserRow): Promise<AuthResult> {
  const accessToken = signAccessToken({
    sub: user.id_user,
    role: user.role,
    session: user.role === 'learner' ? user.session : undefined,
  });
  const rt = generateRefreshToken();
  await insertRefreshToken({
    userId: user.id_user,
    tokenHash: rt.hash,
    expiresAt: rt.expiresAt,
  });
  return {
    accessToken,
    refreshToken: rt.token,
    expiresIn: ACCESS_TTL_SECONDS,
  };
}

export async function login(username: string, password: string): Promise<LoginResult> {
  const user = await findUserByUsername(username);
  if (!user) throw new AppError('invalid_credentials');
  const ok = await verifyPassword(password, user.password);
  if (!ok) throw new AppError('invalid_credentials');
  const tokens = await issueTokensFor(user);
  return { ...tokens, user: toPublicUser(user) };
}

export async function refresh(refreshToken: string): Promise<AuthResult> {
  const hash = hashRefreshToken(refreshToken);

  // Quick pre-check outside the transaction: if the token is unknown, bail fast.
  const preCheck = await findRefreshTokenByHash(hash);
  if (!preCheck) throw new AppError('invalid_grant');

  // Reuse detection: if already revoked, cascade-revoke all tokens for the user
  // and reject. This path does not need a transaction — the cascade uses the pool.
  if (preCheck.revoked_at !== null) {
    await revokeAllRefreshTokensForUser(preCheck.id_user);
    throw new AppError('invalid_grant');
  }

  // Atomic rotation: SELECT FOR UPDATE inside a transaction ensures only one
  // concurrent request can revoke and replace this token.
  const conn = await pool.getConnection();
  let newRefreshToken: string | null = null;
  let newAccessToken: string | null = null;

  try {
    await conn.beginTransaction();

    const row = await findRefreshTokenByHashForUpdate(conn, hash);
    if (!row || row.revoked_at !== null || row.expires_at.getTime() <= Date.now()) {
      await conn.rollback();
      throw new AppError('invalid_grant');
    }

    const user = await findUserById(row.id_user);
    if (!user) {
      await conn.rollback();
      throw new AppError('invalid_grant');
    }

    const nextRt = generateRefreshToken();
    const newId = await insertRefreshTokenTx(conn, {
      userId: user.id_user,
      tokenHash: nextRt.hash,
      expiresAt: nextRt.expiresAt,
    });
    await revokeRefreshTokenTx(conn, row.id_token, newId);

    await conn.commit();

    newAccessToken = signAccessToken({
      sub: user.id_user,
      role: user.role,
      session: user.role === 'learner' ? user.session : undefined,
    });
    newRefreshToken = nextRt.token;
  } catch (err) {
    // Only rollback if we haven't already committed or rolled back.
    try { await conn.rollback(); } catch { /* already resolved */ }
    throw err;
  } finally {
    conn.release();
  }

  return {
    accessToken: newAccessToken!,
    refreshToken: newRefreshToken!,
    expiresIn: ACCESS_TTL_SECONDS,
  };
}

export async function logout(refreshToken: string): Promise<void> {
  const hash = hashRefreshToken(refreshToken);
  const row = await findRefreshTokenByHash(hash);
  if (!row || row.revoked_at !== null) return;
  await revokeRefreshToken(row.id_token, null);
}
