import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../middleware/requireAuth.js';
import { requireRole } from '../middleware/requireRole.js';
import { requireSignature } from '../middleware/requireSignature.js';
import { presenceRateLimit } from '../middleware/presenceRateLimit.js';
import { AppError } from '../lib/errors.js';
import { recordPresence } from '../services/presenceService.js';

const bodySchema = z.object({
  room_id: z.number().int().positive(),
  position_x: z.number().optional(),
  position_y: z.number().optional(),
  battery_level: z.number().int().min(0).max(100).optional(),
});

export const presenceRouter = Router();

presenceRouter.post('/', requireAuth, requireRole('learner'), requireSignature, presenceRateLimit, async (req, res, next) => {
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    // Use the client's X-Timestamp (from the phone's NTP-synced clock)
    // instead of relying on CURRENT_TIMESTAMP, so presence times are
    // accurate even when the server clock drifts.
    const tsHeader = req.headers['x-timestamp'];
    const clientTime = typeof tsHeader === 'string' && /^\d+$/.test(tsHeader)
      ? new Date(parseInt(tsHeader, 10) * 1000)
      : undefined;
    await recordPresence(req.user!.id, parsed.data, clientTime);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});
