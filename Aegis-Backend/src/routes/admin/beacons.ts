import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../middleware/requireAuth.js';
import { requireRole } from '../../middleware/requireRole.js';
import { AppError } from '../../lib/errors.js';
import {
  listBeaconsService,
  getBeaconService,
  createBeaconService,
  updateBeaconService,
  deleteBeaconService,
} from '../../services/beaconsService.js';

const idParam = z.object({ device_id: z.coerce.number().int().positive() });

const listQuerySchema = z.object({
  assigned: z
    .enum(['true', 'false'])
    .optional()
    .transform((v) => (v === undefined ? undefined : v === 'true')),
  room_id: z.coerce.number().int().positive().optional(),
  page: z.coerce.number().int().min(1).default(1),
  per_page: z.coerce.number().int().min(1).max(100).default(20),
});

const createBodySchema = z.object({
  name: z.string().min(1).max(100),
  beacon_identifier: z.string().min(1).max(100),
  room_id: z.number().int().positive().nullable(),
}).strict();

const patchBodySchema = z.object({
  name: z.string().min(1).max(100).optional(),
  beacon_identifier: z.string().min(1).max(100).optional(),
  room_id: z.number().int().positive().nullable().optional(),
}).strict();

export const beaconsAdminRouter = Router();

beaconsAdminRouter.get('/', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = listQuerySchema.safeParse(req.query);
  if (!parsed.success) return next(new AppError('invalid_request'));
  const { assigned, room_id, page, per_page } = parsed.data;
  try {
    const result = await listBeaconsService(
      { assigned, roomId: room_id },
      page,
      per_page,
    );
    res.json(result);
  } catch (err) {
    next(err);
  }
});

beaconsAdminRouter.get('/:device_id', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = idParam.safeParse(req.params);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    const beacon = await getBeaconService(parsed.data.device_id);
    res.json(beacon);
  } catch (err) {
    next(err);
  }
});

beaconsAdminRouter.post('/', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = createBodySchema.safeParse(req.body);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    const beacon = await createBeaconService(parsed.data);
    res.status(201).json(beacon);
  } catch (err) {
    next(err);
  }
});

beaconsAdminRouter.patch('/:device_id', requireAuth, requireRole('admin'), async (req, res, next) => {
  const idParsed = idParam.safeParse(req.params);
  if (!idParsed.success) return next(new AppError('invalid_request'));
  const bodyParsed = patchBodySchema.safeParse(req.body);
  if (!bodyParsed.success) return next(new AppError('invalid_request'));
  try {
    const beacon = await updateBeaconService(idParsed.data.device_id, bodyParsed.data);
    res.json(beacon);
  } catch (err) {
    next(err);
  }
});

beaconsAdminRouter.delete('/:device_id', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = idParam.safeParse(req.params);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    await deleteBeaconService(parsed.data.device_id);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});
