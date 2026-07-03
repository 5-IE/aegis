import { Router } from 'express';
import { requireAuth } from '../../middleware/requireAuth.js';
import { requireRole } from '../../middleware/requireRole.js';
import { getAbsenceSummary } from '../../services/dashboardService.js';

export const absenceSummaryRouter = Router();

absenceSummaryRouter.get('/', requireAuth, requireRole('admin'), async (_req, res, next) => {
  try {
    const result = await getAbsenceSummary(new Date());
    res.json(result);
  } catch (err) {
    next(err);
  }
});
