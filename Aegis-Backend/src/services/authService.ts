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
} from '../db/queries/refreshTokenQueries.js';

const ACCESS_TTL_SECONDS = 900;

export interface PublicUser {
  id: number;
  username: string;
  role: 'admin' | 'learner';
  session: 'AM' | 'PM';
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
    session: row.session,
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
  const row = await findRefreshTokenByHash(hash);
  if (!row) throw new AppError('invalid_grant');

  if (row.revoked_at !== null) {
    // Reuse detected — cascade revoke all tokens for this user, then reject.
    await revokeAllRefreshTokensForUser(row.id_user);
    throw new AppError('invalid_grant');
  }
  if (row.expires_at.getTime() <= Date.now()) {
    throw new AppError('invalid_grant');
  }

  const user = await findUserById(row.id_user);
  if (!user) throw new AppError('invalid_grant');

  const accessToken = signAccessToken({
    sub: user.id_user,
    role: user.role,
    session: user.role === 'learner' ? user.session : undefined,
  });
  const nextRt = generateRefreshToken();
  const newId = await insertRefreshToken({
    userId: user.id_user,
    tokenHash: nextRt.hash,
    expiresAt: nextRt.expiresAt,
  });
  await revokeRefreshToken(row.id_token, newId);

  return {
    accessToken,
    refreshToken: nextRt.token,
    expiresIn: ACCESS_TTL_SECONDS,
  };
}

export async function logout(refreshToken: string): Promise<void> {
  const hash = hashRefreshToken(refreshToken);
  const row = await findRefreshTokenByHash(hash);
  if (!row || row.revoked_at !== null) return;
  await revokeRefreshToken(row.id_token, null);
}
