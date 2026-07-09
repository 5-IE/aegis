import { Router } from 'express';
import { requireAuth } from '../middleware/requireAuth.js';
import { requireRole } from '../middleware/requireRole.js';
import { updateDevicePublicKey } from '../db/queries/userQueries.js';
import { AppError } from '../lib/errors.js';

export const registerDeviceRouter = Router();

registerDeviceRouter.post('/', requireAuth, requireRole('learner'), async (req, res, next) => {
  try {
    const { device_public_key } = req.body as { device_public_key?: unknown };
    if (typeof device_public_key !== 'string' || device_public_key.length === 0 || device_public_key.length > 256) {
      throw new AppError('invalid_request', 'device_public_key must be a non-empty string of at most 256 characters');
    }
    await updateDevicePublicKey(req.user!.id, device_public_key);
    res.json({ message: 'Device registered successfully' });
  } catch (err) {
    next(err);
  }
});
