import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../middleware/requireAuth.js';
import { requireRole } from '../../middleware/requireRole.js';
import { AppError } from '../../lib/errors.js';
import { runRollup } from '../../services/rollupService.js';

const bodySchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  user_id: z.number().int().positive().optional(),
}).strict();

export const rollupRouter = Router();

rollupRouter.post('/', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = bodySchema.safeParse(req.body ?? {});
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    const result = await runRollup({ date: parsed.data.date, userId: parsed.data.user_id });
    res.json(result);
  } catch (err) {
    next(err);
  }
});
