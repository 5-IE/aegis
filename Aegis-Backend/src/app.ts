import express from 'express';
import { authRouter } from './routes/auth.js';
import { meRouter } from './routes/me.js';
import { dashboardRouter } from './routes/dashboard.js';
import { historiesRouter } from './routes/histories.js';
import { presenceRouter } from './routes/presence.js';
import { beaconsRouter } from './routes/beacons.js';
import { absenceSummaryRouter } from './routes/admin/absenceSummary.js';
import { adminOverviewRouter } from './routes/admin/overview.js';
import { adminRoomsRouter } from './routes/admin/rooms.js';
import { sessionConfigRouter } from './routes/admin/sessionConfig.js';
import { systemConfigRouter } from './routes/admin/systemConfig.js';
import { rollupRouter } from './routes/admin/rollup.js';
import { usersRouter } from './routes/admin/users.js';
import { beaconsAdminRouter } from './routes/admin/beacons.js';
import { errorHandler } from './middleware/errorHandler.js';

export function buildApp(): express.Express {
  const app = express();
  app.set('trust proxy', 1);
  app.use(express.json({ limit: '64kb' }));

  app.get('/health', (_req, res) => {
    res.json({ status: 'ok' });
  });

  app.use('/auth', authRouter);

  app.use('/api/v1/me', meRouter);
  app.use('/api/v1/dashboard', dashboardRouter);
  app.use('/api/v1/histories', historiesRouter);
  app.use('/api/v1/presence', presenceRouter);
  app.use('/api/v1/beacons', beaconsRouter);

  app.use('/api/v1/admin/absence-summary', absenceSummaryRouter);
  app.use('/api/v1/admin/overview', adminOverviewRouter);
  app.use('/api/v1/admin/rooms', adminRoomsRouter);
  app.use('/api/v1/admin/session-config', sessionConfigRouter);
  app.use('/api/v1/admin/system-config', systemConfigRouter);
  app.use('/api/v1/admin/rollup', rollupRouter);
  app.use('/api/v1/admin/users', usersRouter);
  app.use('/api/v1/admin/beacons', beaconsAdminRouter);

  app.use(errorHandler);
  return app;
}
