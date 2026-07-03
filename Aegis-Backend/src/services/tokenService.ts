import crypto from 'node:crypto';
import jwt from 'jsonwebtoken';
import { config } from '../lib/config.js';
import { AppError } from '../lib/errors.js';

const ACCESS_TTL_SECONDS = 900;
const REFRESH_TTL_MS = 30 * 24 * 60 * 60 * 1000;

export type Role = 'admin' | 'learner';
export type Session = 'AM' | 'PM';

export interface AccessTokenClaims {
  sub: number;
  role: Role;
  session?: Session;
  iat: number;
  exp: number;
  iss: 'aegis';
}

export function signAccessToken(payload: {
  sub: number;
  role: Role;
  session?: Session;
}): string {
  const claims: Record<string, unknown> = {
    sub: payload.sub,
    role: payload.role,
  };
  if (payload.session) claims.session = payload.session;
  return jwt.sign(claims, config.jwtSecret, {
    algorithm: 'HS256',
    expiresIn: ACCESS_TTL_SECONDS,
    issuer: 'aegis',
  });
}

export function verifyAccessToken(token: string): AccessTokenClaims {
  try {
    const decoded = jwt.verify(token, config.jwtSecret, {
      algorithms: ['HS256'],
      issuer: 'aegis',
    });
    if (typeof decoded !== 'object' || decoded === null) {
      throw new AppError('unauthorized', 'unauthorized');
    }
    return decoded as AccessTokenClaims;
  } catch (err) {
    if (err instanceof AppError) throw err;
    throw new AppError('unauthorized', 'unauthorized');
  }
}

export function hashRefreshToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}

export function generateRefreshToken(): { token: string; hash: string; expiresAt: Date } {
  const token = crypto.randomBytes(32).toString('base64url');
  return {
    token,
    hash: hashRefreshToken(token),
    expiresAt: new Date(Date.now() + REFRESH_TTL_MS),
  };
}
