import type { ErrorRequestHandler } from 'express';
import { AppError } from '../lib/errors.js';
import { logger } from '../lib/logger.js';

export const errorHandler: ErrorRequestHandler = (err, _req, res, _next) => {
  if (err instanceof AppError) {
    res.status(err.status).json({ error: err.code, message: err.message });
    return;
  }
  logger.error({ err }, 'Unhandled error');
  res.status(500).json({ error: 'internal_error', message: 'An unexpected error occurred' });
};
