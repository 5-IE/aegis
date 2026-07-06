import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../../middleware/requireAuth.js';
import { requireRole } from '../../middleware/requireRole.js';
import { AppError } from '../../lib/errors.js';
import {
  listUsersService,
  getUserService,
  createUserService,
  updateUserService,
  resetPasswordService,
  deleteUserService,
  reactivateUserService,
} from '../../services/userService.js';

const idParam = z.object({ id: z.coerce.number().int().positive() });

const listQuerySchema = z.object({
  role: z.enum(['admin', 'learner']).optional(),
  session: z.enum(['AM', 'PM']).optional(),
  name: z.string().max(100).optional(),
  include_inactive: z
    .enum(['true', 'false'])
    .optional()
    .transform((v) => v === 'true'),
  page: z.coerce.number().int().min(1).default(1),
  per_page: z.coerce.number().int().min(1).max(100).default(20),
});

const createBodySchema = z.object({
  username: z.string().min(1).max(50),
  password: z.string().min(1).max(72),
  email: z.string().email().max(100),
  role: z.enum(['admin', 'learner']),
  session: z.enum(['AM', 'PM']).optional(),
  first_name: z.string().max(50).nullable().optional(),
  last_name: z.string().max(50).nullable().optional(),
}).strict();

const patchBodySchema = z.object({
  email: z.string().email().max(100).optional(),
  role: z.enum(['admin', 'learner']).optional(),
  session: z.enum(['AM', 'PM']).optional(),
  first_name: z.string().max(50).nullable().optional(),
  last_name: z.string().max(50).nullable().optional(),
}).strict();

const passwordBodySchema = z.object({
  new_password: z.string().min(1).max(72),
}).strict();

export const usersRouter = Router();

usersRouter.get('/', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = listQuerySchema.safeParse(req.query);
  if (!parsed.success) return next(new AppError('invalid_request'));
  const { role, session, name, include_inactive, page, per_page } = parsed.data;
  try {
    const result = await listUsersService(
      { role, session, name, includeInactive: include_inactive },
      page,
      per_page,
    );
    res.json(result);
  } catch (err) {
    next(err);
  }
});

usersRouter.get('/:id', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = idParam.safeParse(req.params);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    const user = await getUserService(parsed.data.id);
    res.json(user);
  } catch (err) {
    next(err);
  }
});

usersRouter.post('/', requireAuth, requireRole('admin'), async (req, res, next) => {
  const parsed = createBodySchema.safeParse(req.body);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    const user = await createUserService(parsed.data);
    res.status(201).json(user);
  } catch (err) {
    next(err);
  }
});

usersRouter.patch('/:id', requireAuth, requireRole('admin'), async (req, res, next) => {
  const idParsed = idParam.safeParse(req.params);
  if (!idParsed.success) return next(new AppError('invalid_request'));
  const bodyParsed = patchBodySchema.safeParse(req.body);
  if (!bodyParsed.success) return next(new AppError('invalid_request'));
  try {
    const user = await updateUserService(idParsed.data.id, bodyParsed.data);
    res.json(user);
  } catch (err) {
    next(err);
  }
});

usersRouter.put('/:id/password', requireAuth, requireRole('admin'), async (req, res, next) => {
  const idParsed = idParam.safeParse(req.params);
  if (!idParsed.success) return next(new AppError('invalid_request'));
  const bodyParsed = passwordBodySchema.safeParse(req.body);
  if (!bodyParsed.success) return next(new AppError('invalid_request'));
  try {
    await resetPasswordService(idParsed.data.id, bodyParsed.data.new_password);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});

usersRouter.delete('/:id', requireAuth, requireRole('admin'), async (req, res, next) => {
  const idParsed = idParam.safeParse(req.params);
  if (!idParsed.success) return next(new AppError('invalid_request'));
  try {
    await deleteUserService(idParsed.data.id, req.user!.id);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});

usersRouter.post('/:id/reactivate', requireAuth, requireRole('admin'), async (req, res, next) => {
  const idParsed = idParam.safeParse(req.params);
  if (!idParsed.success) return next(new AppError('invalid_request'));
  try {
    await reactivateUserService(idParsed.data.id);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});
