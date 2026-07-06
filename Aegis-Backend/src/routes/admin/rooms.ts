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
  createRoomService,
  updateRoomService,
  deleteRoomService,
} from '../../services/roomsService.js';

const idParam = z.object({ room_id: z.coerce.number().int().positive() });

const createBodySchema = z.object({
  name: z.string().min(1).max(100),
}).strict();

const patchBodySchema = z.object({
  name: z.string().min(1).max(100).optional(),
}).strict();

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

adminRoomsRouter.post('/', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = createBodySchema.safeParse(req.body);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    const room = await createRoomService(parsed.data);
    res.status(201).json(room);
  } catch (err) {
    next(err);
  }
});

adminRoomsRouter.patch('/:room_id', requireAuth, requireRole('admin'), async (req, res, next) => {
  const idParsed = idParam.safeParse(req.params);
  if (!idParsed.success) return next(new AppError('invalid_request'));
  const bodyParsed = patchBodySchema.safeParse(req.body);
  if (!bodyParsed.success) return next(new AppError('invalid_request'));
  try {
    const room = await updateRoomService(idParsed.data.room_id, bodyParsed.data);
    res.json(room);
  } catch (err) {
    next(err);
  }
});

adminRoomsRouter.delete('/:room_id', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = idParam.safeParse(req.params);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    await deleteRoomService(parsed.data.room_id);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});
