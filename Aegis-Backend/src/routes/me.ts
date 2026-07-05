import { Router } from 'express';
import { requireAuth } from '../middleware/requireAuth.js';
import { requireRole } from '../middleware/requireRole.js';
import { findUserById } from '../db/queries/userQueries.js';
import { AppError } from '../lib/errors.js';

export const meRouter = Router();

meRouter.get('/', requireAuth, requireRole('learner'), async (req, res, next) => {
  try {
    const user = await findUserById(req.user!.id);
    if (!user) throw new AppError('not_found', 'User not found');
    res.json({
      id: user.id_user,
      first_name: user.first_name,
      last_name: user.last_name,
      username: user.username,
      email: user.email,
      role: user.role,
      session: user.session,
    });
  } catch (err) {
    next(err);
  }
});
