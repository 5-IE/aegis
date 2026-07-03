import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../middleware/requireAuth.js';
import { requireRole } from '../../middleware/requireRole.js';
import { AppError } from '../../lib/errors.js';
import { getOverview } from '../../services/overviewService.js';

const querySchema = z.object({
  name: z.string().max(100).optional(),
  session: z.enum(['AM', 'PM']).optional(),
  page: z.coerce.number().int().min(1).default(1),
  per_page: z.coerce.number().int().min(1).max(100).default(20),
});

export const adminOverviewRouter = Router();

adminOverviewRouter.get('/', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = querySchema.safeParse(req.query);
  if (!parsed.success) return next(new AppError('invalid_request'));
  const { name, session, page, per_page } = parsed.data;
  try {
    const result = await getOverview(new Date(), { name, session }, page, per_page);
    res.json(result);
  } catch (err) {
    next(err);
  }
});
