import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../middleware/requireAuth.js';
import { requireRole } from '../../middleware/requireRole.js';
import { AppError } from '../../lib/errors.js';
import { getSessionConfigs, updateSessionConfig } from '../../services/configService.js';

const timePattern = /^([01]\d|2[0-3]):[0-5]\d:[0-5]\d$/;
const bodySchema = z.object({
  start_time: z.string().regex(timePattern),
  late_after: z.string().regex(timePattern),
  end_time: z.string().regex(timePattern),
});
const paramSchema = z.object({ session: z.enum(['AM', 'PM']) });

export const sessionConfigRouter = Router();

sessionConfigRouter.get('/', requireAuth, requireRole('admin'), async (_req, res, next) => {
  try {
    const cfgs = await getSessionConfigs();
    res.json({
      AM: { start_time: cfgs.AM.start_time, late_after: cfgs.AM.late_after, end_time: cfgs.AM.end_time },
      PM: { start_time: cfgs.PM.start_time, late_after: cfgs.PM.late_after, end_time: cfgs.PM.end_time },
    });
  } catch (err) {
    next(err);
  }
});

sessionConfigRouter.put('/:session', requireAuth, requireRole('admin'), async (req, res, next) => {
  const p = paramSchema.safeParse(req.params);
  const b = bodySchema.safeParse(req.body);
  if (!p.success || !b.success) return next(new AppError('invalid_request'));
  try {
    await updateSessionConfig(p.data.session, b.data);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});
