import { buildApp } from './app.js';
import { config } from './lib/config.js';
import { logger } from './lib/logger.js';

const app = buildApp();
app.listen(config.port, () => {
  logger.info({ port: config.port }, 'Aegis backend listening');
});
