import 'dotenv/config';
import { logger } from '../src/lib/logger.js';
import { hashPassword } from '../src/services/passwordService.js';
import { findUserByUsername, insertUser } from '../src/db/queries/userQueries.js';
import { pool } from '../src/db/pool.js';

function required(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var: ${name}`);
  return v;
}

async function main() {
  const username = required('SEED_ADMIN_USERNAME');
  const password = required('SEED_ADMIN_PASSWORD');
  const email = required('SEED_ADMIN_EMAIL');

  const existing = await findUserByUsername(username);
  if (existing) {
    logger.info({ username }, 'Admin already exists — skipping');
    await pool.end();
    return;
  }

  const hash = await hashPassword(password);
  const id = await insertUser({
    username,
    passwordHash: hash,
    email,
    role: 'admin',
  });
  logger.info({ username, id }, 'Seeded admin user');
  await pool.end();
}

main().catch((err) => {
  logger.error({ err }, 'Seed failed');
  process.exit(1);
});
