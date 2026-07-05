import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../middleware/requireAuth.js';
import { requireRole } from '../../middleware/requireRole.js';
import { AppError } from '../../lib/errors.js';
import {
  listAllRooms,
  getRoomMap,
  getRoomCurrentOccupants,
  getRoomAdditionalData,
} from '../../services/roomsService.js';

const idParam = z.object({ room_id: z.coerce.number().int().positive() });

export const adminRoomsRouter = Router();

adminRoomsRouter.get('/', requireAuth, requireRole('admin'), async (_req, res, next) => {
  try {
    const rows = await listAllRooms();
    res.json({ list: rows });
  } catch (err) {
    next(err);
  }
});

adminRoomsRouter.get('/:room_id/map', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = idParam.safeParse(req.params);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    const result = await getRoomMap(parsed.data.room_id, new Date());
    res.json(result);
  } catch (err) {
    next(err);
  }
});

adminRoomsRouter.get('/:room_id/current-occupants', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = idParam.safeParse(req.params);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    const result = await getRoomCurrentOccupants(parsed.data.room_id, new Date());
    res.json(result);
  } catch (err) {
    next(err);
  }
});

adminRoomsRouter.get('/:room_id/additional-data', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = idParam.safeParse(req.params);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    const result = await getRoomAdditionalData(parsed.data.room_id, new Date());
    res.json(result);
  } catch (err) {
    next(err);
  }
});
