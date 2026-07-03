import { readdir, readFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import mysql from 'mysql2/promise';
import { config } from '../src/lib/config.js';
import { logger } from '../src/lib/logger.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MIGRATIONS_DIR = join(__dirname, '..', 'migrations');

async function ensureMigrationTable(conn: mysql.Connection) {
  await conn.query(`
    CREATE TABLE IF NOT EXISTS \`SCHEMA_MIGRATIONS\` (
      \`filename\` VARCHAR(255) NOT NULL PRIMARY KEY,
      \`applied_at\` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `);
}

async function appliedFilenames(conn: mysql.Connection): Promise<Set<string>> {
  const [rows] = await conn.query<mysql.RowDataPacket[]>('SELECT filename FROM `SCHEMA_MIGRATIONS`');
  return new Set(rows.map((r) => r.filename as string));
}

async function main() {
  // 0001_init creates the database itself, so connect without a default DB first.
  const bootstrapConn = await mysql.createConnection({
    host: config.db.host,
    port: config.db.port,
    user: config.db.user,
    password: config.db.password,
    multipleStatements: true,
  });

  const files = (await readdir(MIGRATIONS_DIR)).filter((f) => f.endsWith('.sql')).sort();
  if (files.length === 0) {
    logger.info('No migrations found');
    await bootstrapConn.end();
    return;
  }

  // Run 0001 unconditionally if AEGIS db is missing; otherwise skip.
  const [dbs] = await bootstrapConn.query<mysql.RowDataPacket[]>(
    'SHOW DATABASES LIKE ?', [config.db.name],
  );
  const dbExists = dbs.length > 0;
  if (!dbExists) {
    const first = files[0];
    logger.info({ file: first }, 'Applying bootstrap migration');
    const sql = await readFile(join(MIGRATIONS_DIR, first), 'utf8');
    await bootstrapConn.query(sql);
  }
  await bootstrapConn.end();

  const conn = await mysql.createConnection({
    host: config.db.host,
    port: config.db.port,
    user: config.db.user,
    password: config.db.password,
    database: config.db.name,
    multipleStatements: true,
  });

  await ensureMigrationTable(conn);
  const already = await appliedFilenames(conn);

  for (const file of files) {
    if (already.has(file)) {
      logger.info({ file }, 'Skip (already applied)');
      continue;
    }
    logger.info({ file }, 'Applying');
    const sql = await readFile(join(MIGRATIONS_DIR, file), 'utf8');
    await conn.query(sql);
    await conn.query('INSERT INTO `SCHEMA_MIGRATIONS` (filename) VALUES (?)', [file]);
  }

  await conn.end();
  logger.info('Migrations complete');
}

main().catch((err) => {
  logger.error({ err }, 'Migration failed');
  process.exit(1);
});
