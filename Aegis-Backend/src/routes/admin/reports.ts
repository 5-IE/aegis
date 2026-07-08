import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../middleware/requireAuth.js';
import { requireRole } from '../../middleware/requireRole.js';
import { AppError } from '../../lib/errors.js';
import { getAttendanceReport, reportRecordsToCsv } from '../../services/reportsService.js';

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const MAX_RANGE_DAYS = 92;

const attendanceQuerySchema = z.object({
  from: z.string().regex(DATE_RE),
  to: z.string().regex(DATE_RE),
  session: z.enum(['AM', 'PM']).optional(),
  user_id: z.coerce.number().int().positive().optional(),
  format: z.literal('csv').optional(),
}).strict();

function rangeDays(from: string, to: string): number {
  const [fy, fm, fd] = from.split('-').map((x) => Number.parseInt(x, 10));
  const [ty, tm, td] = to.split('-').map((x) => Number.parseInt(x, 10));
  const ms = Date.UTC(ty, tm - 1, td) - Date.UTC(fy, fm - 1, fd);
  return ms / (24 * 60 * 60 * 1000) + 1;
}

export const adminReportsRouter = Router();

adminReportsRouter.get('/attendance', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = attendanceQuerySchema.safeParse(req.query);
  if (!parsed.success) return next(new AppError('invalid_request'));
  const { from, to, session, user_id, format } = parsed.data;
  if (from > to) return next(new AppError('invalid_request', 'from must be on or before to'));
  if (rangeDays(from, to) > MAX_RANGE_DAYS) {
    return next(new AppError('invalid_request', `Date range must not exceed ${MAX_RANGE_DAYS} days`));
  }
  try {
    const report = await getAttendanceReport({ from, to, session, userId: user_id });
    if (format === 'csv') {
      res.setHeader('Content-Type', 'text/csv; charset=utf-8');
      res.setHeader('Content-Disposition', `attachment; filename=aegis-attendance-${from}-${to}.csv`);
      res.send(reportRecordsToCsv(report.records));
      return;
    }
    res.json(report);
  } catch (err) {
    next(err);
  }
});
