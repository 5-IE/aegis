import { Router } from 'express';
import { z } from 'zod';
import { AppError } from '../lib/errors.js';
import { login, refresh, logout } from '../services/authService.js';
import { authRateLimit } from '../middleware/rateLimit.js';

const loginSchema = z.object({
  username: z.string().min(1).max(50),
  // bcrypt silently truncates at 72 bytes; cap here to prevent silent truncation
  password: z.string().min(1).max(72),
});

const refreshSchema = z.object({
  // Real refresh tokens are ~43 chars; cap at 256 to reject garbage early
  refresh_token: z.string().min(1).max(256),
});

const logoutSchema = z.object({
  // Real refresh tokens are ~43 chars; cap at 256 to reject garbage early
  refresh_token: z.string().min(1).max(256),
});

export const authRouter = Router();

authRouter.post('/login', authRateLimit, async (req, res, next) => {
  const parsed = loginSchema.safeParse(req.body);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    const result = await login(parsed.data.username, parsed.data.password);
    res.status(200).json({
      access_token: result.accessToken,
      refresh_token: result.refreshToken,
      expires_in: result.expiresIn,
      user: result.user,
    });
  } catch (err) {
    next(err);
  }
});

authRouter.post('/refresh', authRateLimit, async (req, res, next) => {
  const parsed = refreshSchema.safeParse(req.body);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    const result = await refresh(parsed.data.refresh_token);
    res.status(200).json({
      access_token: result.accessToken,
      refresh_token: result.refreshToken,
      expires_in: result.expiresIn,
    });
  } catch (err) {
    next(err);
  }
});

authRouter.post('/logout', async (req, res, next) => {
  const parsed = logoutSchema.safeParse(req.body);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    await logout(parsed.data.refresh_token);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});
