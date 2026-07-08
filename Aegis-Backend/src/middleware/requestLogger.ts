import type { RequestHandler } from 'express';
import { logger } from '../lib/logger.js';

/**
 * Logs one line per request on completion: method, path, status, duration, and
 * the authenticated user id (once requireAuth has run). Enough to correlate a
 * client call with what the server actually did — e.g. confirm a POST /presence
 * reached this server and returned 204.
 */
export const requestLogger: RequestHandler = (req, res, next) => {
  const start = process.hrtime.bigint();
  res.on('finish', () => {
    const durationMs = Number(process.hrtime.bigint() - start) / 1e6;
    logger.info(
      {
        method: req.method,
        path: req.originalUrl.split('?')[0],
        status: res.statusCode,
        durationMs: Math.round(durationMs * 10) / 10,
        userId: req.user?.id ?? null,
        ip: req.ip,
      },
      'request',
    );
  });
  next();
};
