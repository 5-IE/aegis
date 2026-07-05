import rateLimit from 'express-rate-limit';
import type { Request } from 'express';

export const presenceRateLimit = rateLimit({
  windowMs: 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req: Request) => String(req.user?.id ?? req.ip ?? 'unknown'),
  message: { error: 'too_many_requests', message: 'Too many requests — please try again later' },
});
