import { buildApp } from './app.js';
import { config } from './lib/config.js';
import { logger } from './lib/logger.js';

const app = buildApp();
app.listen(config.port, () => {
  logger.info(
    {
      port: config.port,
      db: { host: config.db.host, port: config.db.port, name: config.db.name, user: config.db.user },
      nodeEnv: process.env.NODE_ENV ?? 'undefined',
    },
    'Aegis backend listening',
  );
});
