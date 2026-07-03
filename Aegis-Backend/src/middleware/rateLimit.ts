import rateLimit from 'express-rate-limit';
import type { Request } from 'express';

function keyFor(req: Request): string {
  const ip = req.ip ?? 'unknown';
  const username = typeof req.body?.username === 'string' ? req.body.username : '';
  return `${ip}:${username}`;
}

export const authRateLimit = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: keyFor,
  skipSuccessfulRequests: true,
  message: { error: 'too_many_requests', message: 'Too many requests — please try again later' },
});
