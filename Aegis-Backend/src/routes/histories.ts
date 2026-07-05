import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../middleware/requireAuth.js';
import { requireRole } from '../middleware/requireRole.js';
import { AppError } from '../lib/errors.js';
import { listHistoriesByUser } from '../db/queries/attendanceHistoryQueries.js';
import { firstPingForUserInWindow, lastPingForUserInWindow } from '../db/queries/presenceQueries.js';
import { getSystemConfig } from '../services/configService.js';
import { combineLocalDateAndTime } from '../services/statusService.js';

const querySchema = z.object({
  month: z.coerce.number().int().min(1).max(12).optional(),
  year: z.coerce.number().int().min(1970).max(9999).optional(),
  page: z.coerce.number().int().min(1).default(1),
  per_page: z.coerce.number().int().min(1).max(100).default(20),
}).refine((v) => !(v.month !== undefined && v.year === undefined), {
  message: 'month requires year',
});

export const historiesRouter = Router();

historiesRouter.get('/', requireAuth, requireRole('learner'), async (req, res, next) => {
  const parsed = querySchema.safeParse(req.query);
  if (!parsed.success) return next(new AppError('invalid_request'));
  const { month, year, page, per_page } = parsed.data;
  try {
    const { list, total } = await listHistoriesByUser(req.user!.id, { month, year }, page, per_page);
    const sys = await getSystemConfig();
    const enriched = await Promise.all(list.map(async (row) => {
      const startUtc = combineLocalDateAndTime(row.date, '00:00:00', sys.timezone);
      const endUtc = new Date(startUtc.getTime() + 24 * 60 * 60 * 1000);
      const [first, last] = await Promise.all([
        firstPingForUserInWindow(req.user!.id, startUtc, endUtc),
        lastPingForUserInWindow(req.user!.id, startUtc, endUtc),
      ]);
      return {
        date: row.date,
        checked_in_at: first ? first.toISOString() : null,
        checked_out_at: last ? last.toISOString() : null,
        status: row.status,
      };
    }));
    res.json({ list: enriched, page, per_page, total });
  } catch (err) {
    next(err);
  }
});
