import express from 'express';
import { authRouter } from './routes/auth.js';
import { errorHandler } from './middleware/errorHandler.js';

export function buildApp(): express.Express {
  const app = express();
  // trust the first proxy hop for req.ip; adjust when adding multi-hop infra
  app.set('trust proxy', 1);
  app.use(express.json({ limit: '64kb' }));
  app.get('/health', (_req, res) => {
    res.json({ status: 'ok' });
  });
  app.use('/auth', authRouter);
  app.use(errorHandler);
  return app;
}
