import { Router } from 'express';
import { requireAuth } from '../middleware/requireAuth.js';
import { requireRole } from '../middleware/requireRole.js';
import { getLearnerDashboard } from '../services/dashboardService.js';

export const dashboardRouter = Router();

dashboardRouter.get('/', requireAuth, requireRole('learner'), async (req, res, next) => {
  try {
    const result = await getLearnerDashboard(req.user!.id, new Date());
    res.json(result);
  } catch (err) {
    next(err);
  }
});
