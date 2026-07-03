import 'dotenv/config';
import { logger } from '../src/lib/logger.js';
import { runRollup } from '../src/services/rollupService.js';
import { pool } from '../src/db/pool.js';

function parseArgs(): { date?: string; userId?: number } {
  const args = process.argv.slice(2);
  const out: { date?: string; userId?: number } = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--date') out.date = args[++i];
    else if (args[i] === '--user-id') out.userId = Number.parseInt(args[++i], 10);
  }
  return out;
}

async function main() {
  const opts = parseArgs();
  const result = await runRollup(opts);
  logger.info({ ...result, ...opts }, 'Rollup complete');
  await pool.end();
}

main().catch(async (err) => {
  logger.error({ err }, 'Rollup failed');
  await pool.end();
  process.exit(1);
});
