import type { Request, Response, NextFunction } from 'express';
import { AppError } from '../lib/errors.js';
import { verifyAccessToken } from '../services/tokenService.js';

export interface AuthUser {
  id: number;
  role: 'admin' | 'learner';
  session?: 'AM' | 'PM';
}

declare module 'express-serve-static-core' {
  interface Request {
    user?: AuthUser;
  }
}

export function requireAuth(req: Request, _res: Response, next: NextFunction): void {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    return next(new AppError('unauthorized'));
  }
  const token = header.slice('Bearer '.length).trim();
  try {
    const claims = verifyAccessToken(token);
    req.user = {
      id: claims.sub,
      role: claims.role,
      session: claims.session,
    };
    next();
  } catch (err) {
    next(err);
  }
}
