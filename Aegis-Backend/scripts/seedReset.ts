import 'dotenv/config';
import { logger } from '../src/lib/logger.js';
import { pool } from '../src/db/pool.js';

/**
 * Truncate all mutable tables so a fresh dev seed can populate them.
 * Preserves migration state and config tables (SESSION_CONFIG, SYSTEM_CONFIG).
 *
 * Guarded by AEGIS_SEED_DEV=1 or --force so it can never be run by accident.
 */

function isGuarded(): boolean {
  if (process.env.AEGIS_SEED_DEV === '1') return true;
  if (process.argv.includes('--force')) return true;
  return false;
}

async function main() {
  if (!isGuarded()) {
    logger.error('seedReset refused: set AEGIS_SEED_DEV=1 or pass --force to run');
    process.exit(2);
  }

  logger.info('Wiping mutable tables (USER, ROOM, DEVICE, PRESENCE_LOG, ATTENDANCE_HISTORY, REFRESH_TOKEN)');

  // FK order matters. Disable checks so we can TRUNCATE cleanly, then re-enable.
  await pool.query('SET FOREIGN_KEY_CHECKS = 0');
  const tables = [
    'REFRESH_TOKEN',
    'ATTENDANCE_HISTORY',
    'PRESENCE_LOG',
    'DEVICE',
    'ROOM',
    'USER',
  ];
  for (const t of tables) {
    await pool.query(`TRUNCATE TABLE \`${t}\``);
    logger.info({ table: t }, 'Truncated');
  }
  await pool.query('SET FOREIGN_KEY_CHECKS = 1');

  logger.info('Reset complete');
  await pool.end();
}

main().catch(async (err) => {
  logger.error({ err }, 'Reset failed');
  await pool.end();
  process.exit(1);
});
