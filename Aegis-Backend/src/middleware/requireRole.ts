import type { RequestHandler } from 'express';
import { AppError } from '../lib/errors.js';

export function requireRole(role: 'admin' | 'learner'): RequestHandler {
  return (req, _res, next) => {
    if (!req.user) return next(new AppError('unauthorized'));
    if (req.user.role !== role) return next(new AppError('forbidden'));
    next();
  };
}
