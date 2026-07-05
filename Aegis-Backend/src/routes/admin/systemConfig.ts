import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../middleware/requireAuth.js';
import { requireRole } from '../../middleware/requireRole.js';
import { AppError } from '../../lib/errors.js';
import { getSystemConfig, updateSystemConfig } from '../../services/configService.js';

const bodySchema = z.object({
  presence_staleness_minutes: z.number().int().min(1).max(60).optional(),
  timezone: z.string().min(1).max(64).optional(),
}).strict();

export const systemConfigRouter = Router();

systemConfigRouter.get('/', requireAuth, requireRole('admin'), async (_req, res, next) => {
  try {
    const cfg = await getSystemConfig();
    res.json(cfg);
  } catch (err) {
    next(err);
  }
});

systemConfigRouter.put('/', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = bodySchema.safeParse(req.body);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    await updateSystemConfig(parsed.data);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});
