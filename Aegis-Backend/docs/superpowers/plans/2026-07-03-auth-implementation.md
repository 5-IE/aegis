# Aegis Auth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Aegis backend authentication subsystem — `/auth/login`, `/auth/refresh`, `/auth/logout` — plus the JWT and role middleware that later feature endpoints will depend on.

**Architecture:** Node.js + TypeScript + Express. Plain JWT auth (HS256, 15-minute access tokens) with rotating opaque refresh tokens (30 days) stored SHA256-hashed in MySQL. Password storage via bcrypt (cost 12). Layered: routes → services → db queries. Services are pure logic and consume query functions, so tests mock at the query layer.

**Tech Stack:** Node 20+, TypeScript 5, Express 4, `mysql2/promise`, `bcrypt`, `jsonwebtoken`, `zod`, `express-rate-limit`, `pino`, `dotenv`, Vitest, supertest.

## Global Constraints

- All source is TypeScript strict mode.
- Node 20+; use ES modules (`"type": "module"` in `package.json`).
- Every service and route ships with a unit test that mocks the DB query layer.
- DB access lives only in `src/db/queries/*` — no `mysql2` imports elsewhere.
- No plaintext credential or token value is ever logged.
- `JWT_SECRET`, DB credentials, and seed admin vars are required env; boot fails fast if missing.
- Password hash uses bcrypt cost factor 12.
- JWT signing uses HS256 with issuer claim `"aegis"`.
- Refresh token: 32 random bytes, base64url-encoded, stored as SHA256 hex hash.
- Access token lifetime: 900 seconds (15 min). Refresh token lifetime: 2592000 seconds (30 days).
- Error response shape: `{ "error": "<code>", "message": "<human text>" }`.

---

## File Structure

**Created:**
- `Aegis-Backend/package.json`, `tsconfig.json`, `.env.example`, `.eslintrc.cjs`, `.prettierrc`, `vitest.config.ts`
- `Aegis-Backend/src/lib/config.ts` — env var loading and validation
- `Aegis-Backend/src/lib/logger.ts` — pino instance
- `Aegis-Backend/src/lib/errors.ts` — typed `AppError` and error codes
- `Aegis-Backend/src/db/pool.ts` — mysql2 pool
- `Aegis-Backend/src/db/queries/userQueries.ts` — user lookups
- `Aegis-Backend/src/db/queries/refreshTokenQueries.ts` — refresh token CRUD
- `Aegis-Backend/src/services/passwordService.ts` — bcrypt hash/verify
- `Aegis-Backend/src/services/tokenService.ts` — JWT + refresh token primitives
- `Aegis-Backend/src/services/authService.ts` — login/refresh/logout logic
- `Aegis-Backend/src/middleware/requireAuth.ts`
- `Aegis-Backend/src/middleware/requireRole.ts`
- `Aegis-Backend/src/middleware/rateLimit.ts`
- `Aegis-Backend/src/middleware/errorHandler.ts`
- `Aegis-Backend/src/routes/auth.ts`
- `Aegis-Backend/src/app.ts` — express app factory
- `Aegis-Backend/src/server.ts` — boot entry point
- `Aegis-Backend/migrations/0001_init.sql` (copied from `docs/aegis.sql`)
- `Aegis-Backend/migrations/0002_bcrypt_password.sql`
- `Aegis-Backend/migrations/0003_refresh_token.sql`
- `Aegis-Backend/scripts/migrate.ts` — apply migrations in order
- `Aegis-Backend/scripts/seed.ts` — first admin bootstrap
- `Aegis-Backend/tests/services/passwordService.test.ts`
- `Aegis-Backend/tests/services/tokenService.test.ts`
- `Aegis-Backend/tests/services/authService.test.ts`
- `Aegis-Backend/tests/middleware/requireAuth.test.ts`
- `Aegis-Backend/tests/middleware/requireRole.test.ts`
- `Aegis-Backend/tests/routes/auth.test.ts`

**Modified:**
- `Aegis-Backend/.gitignore` — add `node_modules`, `dist`, `.env`, coverage

**Untouched:**
- `Aegis-Backend/docs/aegis.sql` — historical; migrations are canonical going forward.

---

## Task 1: Project scaffold

**Files:**
- Create: `Aegis-Backend/package.json`
- Create: `Aegis-Backend/tsconfig.json`
- Create: `Aegis-Backend/.env.example`
- Create: `Aegis-Backend/vitest.config.ts`
- Create: `Aegis-Backend/.eslintrc.cjs`
- Create: `Aegis-Backend/.prettierrc`
- Modify: `Aegis-Backend/.gitignore`

**Interfaces:**
- Consumes: nothing
- Produces: a runnable `npm test`, `npm run build`, `npm run dev`; every later task depends on this

- [ ] **Step 1: Create `Aegis-Backend/package.json`**

```json
{
  "name": "aegis-backend",
  "version": "0.1.0",
  "type": "module",
  "private": true,
  "scripts": {
    "build": "tsc",
    "dev": "tsx watch src/server.ts",
    "start": "node dist/server.js",
    "test": "vitest run",
    "test:watch": "vitest",
    "migrate": "tsx scripts/migrate.ts",
    "seed": "tsx scripts/seed.ts",
    "lint": "eslint src tests scripts",
    "format": "prettier --write ."
  },
  "dependencies": {
    "bcrypt": "^5.1.1",
    "dotenv": "^16.4.5",
    "express": "^4.19.2",
    "express-rate-limit": "^7.4.0",
    "jsonwebtoken": "^9.0.2",
    "mysql2": "^3.11.0",
    "pino": "^9.3.2",
    "pino-pretty": "^11.2.2",
    "zod": "^3.23.8"
  },
  "devDependencies": {
    "@types/bcrypt": "^5.0.2",
    "@types/express": "^4.17.21",
    "@types/jsonwebtoken": "^9.0.6",
    "@types/node": "^20.14.10",
    "@types/supertest": "^6.0.2",
    "@typescript-eslint/eslint-plugin": "^7.16.1",
    "@typescript-eslint/parser": "^7.16.1",
    "eslint": "^8.57.0",
    "prettier": "^3.3.3",
    "supertest": "^7.0.0",
    "tsx": "^4.16.2",
    "typescript": "^5.5.3",
    "vitest": "^2.0.3"
  }
}
```

- [ ] **Step 2: Create `Aegis-Backend/tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "outDir": "dist",
    "rootDir": ".",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": false,
    "sourceMap": true,
    "types": ["node"]
  },
  "include": ["src/**/*.ts", "scripts/**/*.ts", "tests/**/*.ts"]
}
```

- [ ] **Step 3: Create `Aegis-Backend/.env.example`**

```env
PORT=3000
LOG_LEVEL=info

DB_HOST=localhost
DB_PORT=3306
DB_USER=aegis
DB_PASSWORD=changeme
DB_NAME=AEGIS

JWT_SECRET=replace-with-at-least-32-random-bytes-base64

SEED_ADMIN_USERNAME=admin
SEED_ADMIN_PASSWORD=changeme
SEED_ADMIN_EMAIL=admin@aegis.local
```

- [ ] **Step 4: Create `Aegis-Backend/vitest.config.ts`**

```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['tests/**/*.test.ts'],
    globals: false,
    clearMocks: true,
  },
});
```

- [ ] **Step 5: Create `Aegis-Backend/.eslintrc.cjs`**

```js
module.exports = {
  parser: '@typescript-eslint/parser',
  parserOptions: { ecmaVersion: 2022, sourceType: 'module' },
  plugins: ['@typescript-eslint'],
  extends: ['eslint:recommended', 'plugin:@typescript-eslint/recommended'],
  root: true,
  env: { node: true, es2022: true },
};
```

- [ ] **Step 6: Create `Aegis-Backend/.prettierrc`**

```json
{
  "singleQuote": true,
  "semi": true,
  "trailingComma": "all",
  "printWidth": 100
}
```

- [ ] **Step 7: Replace `Aegis-Backend/.gitignore` contents**

```
node_modules/
dist/
coverage/
.env
.env.local
*.log
.DS_Store
```

- [ ] **Step 8: Install dependencies**

Run: `cd Aegis-Backend && npm install`
Expected: exit 0, `node_modules` populated, no vulnerabilities of high severity.

- [ ] **Step 9: Sanity build**

Create a temporary `src/index.ts` containing `console.log('ok');`, then:
Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.
Remove `src/index.ts` after.

- [ ] **Step 10: Commit**

```bash
cd Aegis-Backend
git add package.json package-lock.json tsconfig.json .env.example vitest.config.ts .eslintrc.cjs .prettierrc .gitignore
git commit -m "chore: scaffold TypeScript project for auth subsystem"
```

---

## Task 2: Config, logger, errors

**Files:**
- Create: `Aegis-Backend/src/lib/config.ts`
- Create: `Aegis-Backend/src/lib/logger.ts`
- Create: `Aegis-Backend/src/lib/errors.ts`
- Create: `Aegis-Backend/tests/lib/config.test.ts`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `config: { port: number; logLevel: string; jwtSecret: string; db: { host: string; port: number; user: string; password: string; name: string } }` from `src/lib/config.ts`
  - `logger: pino.Logger` from `src/lib/logger.ts`
  - `class AppError extends Error { code: ErrorCode; status: number; constructor(code, message?) }` and `type ErrorCode = 'invalid_request' | 'invalid_credentials' | 'invalid_grant' | 'unauthorized' | 'forbidden' | 'too_many_requests' | 'internal_error'` from `src/lib/errors.ts`

- [ ] **Step 1: Write failing test `tests/lib/config.test.ts`**

```ts
import { describe, it, expect, beforeEach, afterEach } from 'vitest';

describe('config', () => {
  const originalEnv = { ...process.env };

  beforeEach(() => {
    process.env = { ...originalEnv };
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  it('throws when JWT_SECRET is missing', async () => {
    delete process.env.JWT_SECRET;
    await expect(import(`../../src/lib/config.ts?missing=${Date.now()}`)).rejects.toThrow(/JWT_SECRET/);
  });

  it('loads all values when env is complete', async () => {
    process.env.JWT_SECRET = 'x'.repeat(32);
    process.env.DB_HOST = 'localhost';
    process.env.DB_PORT = '3306';
    process.env.DB_USER = 'u';
    process.env.DB_PASSWORD = 'p';
    process.env.DB_NAME = 'AEGIS';
    process.env.PORT = '3000';
    process.env.LOG_LEVEL = 'info';
    const mod = await import(`../../src/lib/config.ts?ok=${Date.now()}`);
    expect(mod.config.jwtSecret.length).toBeGreaterThanOrEqual(32);
    expect(mod.config.db.name).toBe('AEGIS');
    expect(mod.config.port).toBe(3000);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/lib/config.test.ts`
Expected: FAIL — file not found.

- [ ] **Step 3: Create `Aegis-Backend/src/lib/config.ts`**

```ts
import 'dotenv/config';

function required(name: string): string {
  const v = process.env[name];
  if (!v || v.length === 0) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return v;
}

function requiredInt(name: string): number {
  const v = required(name);
  const n = Number.parseInt(v, 10);
  if (!Number.isFinite(n)) {
    throw new Error(`Env var ${name} must be an integer, got: ${v}`);
  }
  return n;
}

const jwtSecret = required('JWT_SECRET');
if (jwtSecret.length < 32) {
  throw new Error('JWT_SECRET must be at least 32 characters');
}

export const config = {
  port: Number.parseInt(process.env.PORT ?? '3000', 10),
  logLevel: process.env.LOG_LEVEL ?? 'info',
  jwtSecret,
  db: {
    host: required('DB_HOST'),
    port: requiredInt('DB_PORT'),
    user: required('DB_USER'),
    password: required('DB_PASSWORD'),
    name: required('DB_NAME'),
  },
} as const;
```

- [ ] **Step 4: Create `Aegis-Backend/src/lib/logger.ts`**

```ts
import pino from 'pino';
import { config } from './config.js';

export const logger = pino({
  level: config.logLevel,
  transport: process.env.NODE_ENV === 'production'
    ? undefined
    : { target: 'pino-pretty', options: { colorize: true } },
});
```

- [ ] **Step 5: Create `Aegis-Backend/src/lib/errors.ts`**

```ts
export type ErrorCode =
  | 'invalid_request'
  | 'invalid_credentials'
  | 'invalid_grant'
  | 'unauthorized'
  | 'forbidden'
  | 'too_many_requests'
  | 'internal_error';

const STATUS: Record<ErrorCode, number> = {
  invalid_request: 400,
  invalid_credentials: 401,
  invalid_grant: 401,
  unauthorized: 401,
  forbidden: 403,
  too_many_requests: 429,
  internal_error: 500,
};

const DEFAULT_MESSAGE: Record<ErrorCode, string> = {
  invalid_request: 'The request is malformed or missing required fields',
  invalid_credentials: 'Username or password is incorrect',
  invalid_grant: 'The refresh token is invalid, expired, or already used',
  unauthorized: 'Authentication is required',
  forbidden: 'You do not have permission to access this resource',
  too_many_requests: 'Too many requests — please try again later',
  internal_error: 'An unexpected error occurred',
};

export class AppError extends Error {
  readonly code: ErrorCode;
  readonly status: number;

  constructor(code: ErrorCode, message?: string) {
    super(message ?? DEFAULT_MESSAGE[code]);
    this.code = code;
    this.status = STATUS[code];
    this.name = 'AppError';
  }
}
```

- [ ] **Step 6: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/lib/config.test.ts`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add src/lib tests/lib
git commit -m "feat(auth): add config, logger, and error types"
```

---

## Task 3: Migrations and migration runner

**Files:**
- Create: `Aegis-Backend/migrations/0001_init.sql`
- Create: `Aegis-Backend/migrations/0002_bcrypt_password.sql`
- Create: `Aegis-Backend/migrations/0003_refresh_token.sql`
- Create: `Aegis-Backend/scripts/migrate.ts`
- Create: `Aegis-Backend/src/db/pool.ts`

**Interfaces:**
- Consumes: `config` from Task 2
- Produces: `pool: mysql.Pool` from `src/db/pool.ts`; a working `npm run migrate`

- [ ] **Step 1: Copy `Aegis-Backend/docs/aegis.sql` to `Aegis-Backend/migrations/0001_init.sql`**

Contents identical to `docs/aegis.sql`. This is the historical baseline.

- [ ] **Step 2: Create `Aegis-Backend/migrations/0002_bcrypt_password.sql`**

```sql
USE `AEGIS`;
ALTER TABLE `USER` MODIFY `password` VARCHAR(72) NOT NULL;
```

- [ ] **Step 3: Create `Aegis-Backend/migrations/0003_refresh_token.sql`**

```sql
USE `AEGIS`;
CREATE TABLE `REFRESH_TOKEN` (
    `id_token` INT AUTO_INCREMENT,
    `id_user` INT NOT NULL,
    `token_hash` CHAR(64) NOT NULL UNIQUE,
    `expires_at` TIMESTAMP NOT NULL,
    `revoked_at` TIMESTAMP NULL,
    `replaced_by_id` INT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id_token`),
    FOREIGN KEY (`id_user`) REFERENCES `USER`(`id_user`) ON DELETE CASCADE,
    FOREIGN KEY (`replaced_by_id`) REFERENCES `REFRESH_TOKEN`(`id_token`) ON DELETE SET NULL,
    INDEX `idx_user` (`id_user`),
    INDEX `idx_expires` (`expires_at`)
);
```

- [ ] **Step 4: Create `Aegis-Backend/src/db/pool.ts`**

```ts
import mysql from 'mysql2/promise';
import { config } from '../lib/config.js';

export const pool = mysql.createPool({
  host: config.db.host,
  port: config.db.port,
  user: config.db.user,
  password: config.db.password,
  database: config.db.name,
  waitForConnections: true,
  connectionLimit: 10,
  namedPlaceholders: true,
});
```

- [ ] **Step 5: Create `Aegis-Backend/scripts/migrate.ts`**

```ts
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
```

- [ ] **Step 6: Type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
git add migrations scripts/migrate.ts src/db/pool.ts
git commit -m "feat(db): add migrations, migration runner, and connection pool"
```

Note: this task deliberately has no unit tests — the migration runner is I/O-driven boilerplate exercised by running it against a real DB, which is out of scope for v1 tests. Integration testing tracked as tech debt.

---

## Task 4: Password service

**Files:**
- Create: `Aegis-Backend/src/services/passwordService.ts`
- Create: `Aegis-Backend/tests/services/passwordService.test.ts`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `async function hashPassword(plain: string): Promise<string>` — returns bcrypt hash
  - `async function verifyPassword(plain: string, hash: string): Promise<boolean>`

- [ ] **Step 1: Write failing test**

```ts
import { describe, it, expect } from 'vitest';
import { hashPassword, verifyPassword } from '../../src/services/passwordService.js';

describe('passwordService', () => {
  it('hashes a password and verifies correctly', async () => {
    const hash = await hashPassword('hunter2');
    expect(hash).not.toBe('hunter2');
    expect(hash.length).toBeLessThanOrEqual(72);
    expect(await verifyPassword('hunter2', hash)).toBe(true);
  });

  it('rejects wrong password', async () => {
    const hash = await hashPassword('hunter2');
    expect(await verifyPassword('wrong', hash)).toBe(false);
  });

  it('produces different hashes for the same input', async () => {
    const a = await hashPassword('hunter2');
    const b = await hashPassword('hunter2');
    expect(a).not.toBe(b);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/services/passwordService.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Create `src/services/passwordService.ts`**

```ts
import bcrypt from 'bcrypt';

const COST = 12;

export async function hashPassword(plain: string): Promise<string> {
  return bcrypt.hash(plain, COST);
}

export async function verifyPassword(plain: string, hash: string): Promise<boolean> {
  return bcrypt.compare(plain, hash);
}
```

- [ ] **Step 4: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/services/passwordService.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/services/passwordService.ts tests/services/passwordService.test.ts
git commit -m "feat(auth): add bcrypt password hashing service"
```

---

## Task 5: Token service

**Files:**
- Create: `Aegis-Backend/src/services/tokenService.ts`
- Create: `Aegis-Backend/tests/services/tokenService.test.ts`

**Interfaces:**
- Consumes: `config.jwtSecret` from Task 2
- Produces:
  - `type AccessTokenClaims = { sub: number; role: 'admin' | 'learner'; session?: 'AM' | 'PM'; iat: number; exp: number; iss: 'aegis' }`
  - `function signAccessToken(payload: { sub: number; role: 'admin' | 'learner'; session?: 'AM' | 'PM' }): string`
  - `function verifyAccessToken(token: string): AccessTokenClaims` — throws `AppError('unauthorized')` on invalid/expired
  - `function generateRefreshToken(): { token: string; hash: string; expiresAt: Date }` — random 32 bytes base64url; hash is SHA256 hex; expiresAt = now + 30d
  - `function hashRefreshToken(token: string): string` — SHA256 hex

- [ ] **Step 1: Write failing test `tests/services/tokenService.test.ts`**

```ts
import { describe, it, expect, beforeAll } from 'vitest';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

const load = () => import('../../src/services/tokenService.js');

describe('tokenService', () => {
  it('signs and verifies an access token with learner claims', async () => {
    const { signAccessToken, verifyAccessToken } = await load();
    const token = signAccessToken({ sub: 42, role: 'learner', session: 'AM' });
    const claims = verifyAccessToken(token);
    expect(claims.sub).toBe(42);
    expect(claims.role).toBe('learner');
    expect(claims.session).toBe('AM');
    expect(claims.iss).toBe('aegis');
    expect(claims.exp - claims.iat).toBe(900);
  });

  it('signs admin tokens without a session claim', async () => {
    const { signAccessToken, verifyAccessToken } = await load();
    const token = signAccessToken({ sub: 1, role: 'admin' });
    const claims = verifyAccessToken(token);
    expect(claims.role).toBe('admin');
    expect(claims.session).toBeUndefined();
  });

  it('rejects a tampered token', async () => {
    const { signAccessToken, verifyAccessToken } = await load();
    const token = signAccessToken({ sub: 1, role: 'admin' });
    expect(() => verifyAccessToken(token + 'x')).toThrow(/unauthorized/);
  });

  it('generates unique refresh tokens with matching hash', async () => {
    const { generateRefreshToken, hashRefreshToken } = await load();
    const a = generateRefreshToken();
    const b = generateRefreshToken();
    expect(a.token).not.toBe(b.token);
    expect(a.hash).toBe(hashRefreshToken(a.token));
    expect(a.hash).toHaveLength(64);
    expect(a.expiresAt.getTime()).toBeGreaterThan(Date.now());
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/services/tokenService.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Create `src/services/tokenService.ts`**

```ts
import crypto from 'node:crypto';
import jwt from 'jsonwebtoken';
import { config } from '../lib/config.js';
import { AppError } from '../lib/errors.js';

const ACCESS_TTL_SECONDS = 900;
const REFRESH_TTL_MS = 30 * 24 * 60 * 60 * 1000;

export type Role = 'admin' | 'learner';
export type Session = 'AM' | 'PM';

export interface AccessTokenClaims {
  sub: number;
  role: Role;
  session?: Session;
  iat: number;
  exp: number;
  iss: 'aegis';
}

export function signAccessToken(payload: {
  sub: number;
  role: Role;
  session?: Session;
}): string {
  const claims: Record<string, unknown> = {
    sub: payload.sub,
    role: payload.role,
  };
  if (payload.session) claims.session = payload.session;
  return jwt.sign(claims, config.jwtSecret, {
    algorithm: 'HS256',
    expiresIn: ACCESS_TTL_SECONDS,
    issuer: 'aegis',
  });
}

export function verifyAccessToken(token: string): AccessTokenClaims {
  try {
    const decoded = jwt.verify(token, config.jwtSecret, {
      algorithms: ['HS256'],
      issuer: 'aegis',
    });
    if (typeof decoded !== 'object' || decoded === null) {
      throw new AppError('unauthorized');
    }
    return decoded as AccessTokenClaims;
  } catch {
    throw new AppError('unauthorized');
  }
}

export function hashRefreshToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}

export function generateRefreshToken(): { token: string; hash: string; expiresAt: Date } {
  const token = crypto.randomBytes(32).toString('base64url');
  return {
    token,
    hash: hashRefreshToken(token),
    expiresAt: new Date(Date.now() + REFRESH_TTL_MS),
  };
}
```

- [ ] **Step 4: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/services/tokenService.test.ts`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/services/tokenService.ts tests/services/tokenService.test.ts
git commit -m "feat(auth): add JWT and refresh token service"
```

---

## Task 6: DB query functions

**Files:**
- Create: `Aegis-Backend/src/db/queries/userQueries.ts`
- Create: `Aegis-Backend/src/db/queries/refreshTokenQueries.ts`

**Interfaces:**
- Consumes: `pool` from Task 3
- Produces:
  - `interface UserRow { id_user: number; username: string; password: string; email: string; role: 'admin' | 'learner'; first_name: string | null; last_name: string | null; session: 'AM' | 'PM' }`
  - `async function findUserByUsername(username: string): Promise<UserRow | null>`
  - `async function findUserById(id: number): Promise<UserRow | null>`
  - `async function insertUser(input: { username: string; passwordHash: string; email: string; role: 'admin' | 'learner'; firstName?: string; lastName?: string; session?: 'AM' | 'PM' }): Promise<number>` — returns new id
  - `interface RefreshTokenRow { id_token: number; id_user: number; token_hash: string; expires_at: Date; revoked_at: Date | null; replaced_by_id: number | null; created_at: Date }`
  - `async function insertRefreshToken(input: { userId: number; tokenHash: string; expiresAt: Date }): Promise<number>`
  - `async function findRefreshTokenByHash(hash: string): Promise<RefreshTokenRow | null>`
  - `async function revokeRefreshToken(id: number, replacedById: number | null): Promise<void>`
  - `async function revokeAllRefreshTokensForUser(userId: number): Promise<void>`

No unit tests for this task — these are thin wrappers over `pool.query`. They are exercised through mocks in service tests.

- [ ] **Step 1: Create `src/db/queries/userQueries.ts`**

```ts
import { RowDataPacket, ResultSetHeader } from 'mysql2';
import { pool } from '../pool.js';

export interface UserRow {
  id_user: number;
  username: string;
  password: string;
  email: string;
  role: 'admin' | 'learner';
  first_name: string | null;
  last_name: string | null;
  session: 'AM' | 'PM';
}

export async function findUserByUsername(username: string): Promise<UserRow | null> {
  const [rows] = await pool.query<(UserRow & RowDataPacket)[]>(
    'SELECT * FROM `USER` WHERE `username` = ? LIMIT 1',
    [username],
  );
  return rows[0] ?? null;
}

export async function findUserById(id: number): Promise<UserRow | null> {
  const [rows] = await pool.query<(UserRow & RowDataPacket)[]>(
    'SELECT * FROM `USER` WHERE `id_user` = ? LIMIT 1',
    [id],
  );
  return rows[0] ?? null;
}

export async function insertUser(input: {
  username: string;
  passwordHash: string;
  email: string;
  role: 'admin' | 'learner';
  firstName?: string;
  lastName?: string;
  session?: 'AM' | 'PM';
}): Promise<number> {
  const [result] = await pool.query<ResultSetHeader>(
    `INSERT INTO \`USER\`
       (\`username\`, \`password\`, \`email\`, \`role\`, \`first_name\`, \`last_name\`, \`session\`)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    [
      input.username,
      input.passwordHash,
      input.email,
      input.role,
      input.firstName ?? null,
      input.lastName ?? null,
      input.session ?? 'AM',
    ],
  );
  return result.insertId;
}
```

- [ ] **Step 2: Create `src/db/queries/refreshTokenQueries.ts`**

```ts
import { RowDataPacket, ResultSetHeader } from 'mysql2';
import { pool } from '../pool.js';

export interface RefreshTokenRow {
  id_token: number;
  id_user: number;
  token_hash: string;
  expires_at: Date;
  revoked_at: Date | null;
  replaced_by_id: number | null;
  created_at: Date;
}

export async function insertRefreshToken(input: {
  userId: number;
  tokenHash: string;
  expiresAt: Date;
}): Promise<number> {
  const [result] = await pool.query<ResultSetHeader>(
    `INSERT INTO \`REFRESH_TOKEN\` (\`id_user\`, \`token_hash\`, \`expires_at\`)
     VALUES (?, ?, ?)`,
    [input.userId, input.tokenHash, input.expiresAt],
  );
  return result.insertId;
}

export async function findRefreshTokenByHash(hash: string): Promise<RefreshTokenRow | null> {
  const [rows] = await pool.query<(RefreshTokenRow & RowDataPacket)[]>(
    'SELECT * FROM `REFRESH_TOKEN` WHERE `token_hash` = ? LIMIT 1',
    [hash],
  );
  return rows[0] ?? null;
}

export async function revokeRefreshToken(id: number, replacedById: number | null): Promise<void> {
  await pool.query(
    'UPDATE `REFRESH_TOKEN` SET `revoked_at` = NOW(), `replaced_by_id` = ? WHERE `id_token` = ? AND `revoked_at` IS NULL',
    [replacedById, id],
  );
}

export async function revokeAllRefreshTokensForUser(userId: number): Promise<void> {
  await pool.query(
    'UPDATE `REFRESH_TOKEN` SET `revoked_at` = NOW() WHERE `id_user` = ? AND `revoked_at` IS NULL',
    [userId],
  );
}
```

- [ ] **Step 3: Type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add src/db/queries
git commit -m "feat(db): add user and refresh-token query functions"
```

---

## Task 7: Auth service

**Files:**
- Create: `Aegis-Backend/src/services/authService.ts`
- Create: `Aegis-Backend/tests/services/authService.test.ts`

**Interfaces:**
- Consumes:
  - `hashPassword`, `verifyPassword` from `passwordService`
  - `signAccessToken`, `generateRefreshToken`, `hashRefreshToken` from `tokenService`
  - `findUserByUsername`, `findUserById`, `UserRow` from `userQueries`
  - `insertRefreshToken`, `findRefreshTokenByHash`, `revokeRefreshToken`, `revokeAllRefreshTokensForUser` from `refreshTokenQueries`
- Produces:
  - `interface AuthResult { accessToken: string; refreshToken: string; expiresIn: number }`
  - `interface LoginResult extends AuthResult { user: PublicUser }`
  - `interface PublicUser { id: number; username: string; role: 'admin' | 'learner'; session: 'AM' | 'PM'; first_name: string | null; last_name: string | null; email: string }`
  - `async function login(username: string, password: string): Promise<LoginResult>` — throws `AppError('invalid_credentials')`
  - `async function refresh(refreshToken: string): Promise<AuthResult>` — throws `AppError('invalid_grant')`; on reuse, revokes all user tokens
  - `async function logout(refreshToken: string): Promise<void>` — idempotent

- [ ] **Step 1: Write failing test `tests/services/authService.test.ts`**

```ts
import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

vi.mock('../../src/db/queries/userQueries.js', () => ({
  findUserByUsername: vi.fn(),
  findUserById: vi.fn(),
  insertUser: vi.fn(),
}));

vi.mock('../../src/db/queries/refreshTokenQueries.js', () => ({
  insertRefreshToken: vi.fn(),
  findRefreshTokenByHash: vi.fn(),
  revokeRefreshToken: vi.fn(),
  revokeAllRefreshTokensForUser: vi.fn(),
}));

const load = async () => {
  const svc = await import('../../src/services/authService.js');
  const users = await import('../../src/db/queries/userQueries.js');
  const tokens = await import('../../src/db/queries/refreshTokenQueries.js');
  const pw = await import('../../src/services/passwordService.js');
  return { svc, users, tokens, pw };
};

const learner = {
  id_user: 42,
  username: 'alice',
  password: '',
  email: 'a@x',
  role: 'learner' as const,
  first_name: 'Alice',
  last_name: 'Doe',
  session: 'AM' as const,
};

beforeEach(() => vi.clearAllMocks());

describe('login', () => {
  it('returns tokens and user on valid credentials', async () => {
    const { svc, users, tokens, pw } = await load();
    const hash = await pw.hashPassword('hunter2');
    (users.findUserByUsername as any).mockResolvedValue({ ...learner, password: hash });
    (tokens.insertRefreshToken as any).mockResolvedValue(1);

    const result = await svc.login('alice', 'hunter2');
    expect(result.accessToken).toBeTruthy();
    expect(result.refreshToken).toBeTruthy();
    expect(result.expiresIn).toBe(900);
    expect(result.user.id).toBe(42);
    expect(result.user.role).toBe('learner');
    expect(tokens.insertRefreshToken).toHaveBeenCalledOnce();
  });

  it('throws invalid_credentials for unknown user', async () => {
    const { svc, users } = await load();
    (users.findUserByUsername as any).mockResolvedValue(null);
    await expect(svc.login('nobody', 'x')).rejects.toMatchObject({ code: 'invalid_credentials' });
  });

  it('throws invalid_credentials for wrong password', async () => {
    const { svc, users, pw } = await load();
    const hash = await pw.hashPassword('hunter2');
    (users.findUserByUsername as any).mockResolvedValue({ ...learner, password: hash });
    await expect(svc.login('alice', 'wrong')).rejects.toMatchObject({ code: 'invalid_credentials' });
  });
});

describe('refresh', () => {
  it('rotates a valid refresh token', async () => {
    const { svc, tokens, users } = await load();
    const tokenSvc = await import('../../src/services/tokenService.js');
    const gen = tokenSvc.generateRefreshToken();
    (tokens.findRefreshTokenByHash as any).mockResolvedValue({
      id_token: 5,
      id_user: 42,
      token_hash: gen.hash,
      expires_at: new Date(Date.now() + 1000_000),
      revoked_at: null,
      replaced_by_id: null,
      created_at: new Date(),
    });
    (users.findUserById as any).mockResolvedValue(learner);
    (tokens.insertRefreshToken as any).mockResolvedValue(6);

    const result = await svc.refresh(gen.token);
    expect(result.accessToken).toBeTruthy();
    expect(result.refreshToken).not.toBe(gen.token);
    expect(tokens.revokeRefreshToken).toHaveBeenCalledWith(5, 6);
  });

  it('cascade-revokes when a revoked token is reused', async () => {
    const { svc, tokens } = await load();
    const tokenSvc = await import('../../src/services/tokenService.js');
    const gen = tokenSvc.generateRefreshToken();
    (tokens.findRefreshTokenByHash as any).mockResolvedValue({
      id_token: 5,
      id_user: 42,
      token_hash: gen.hash,
      expires_at: new Date(Date.now() + 1000_000),
      revoked_at: new Date(),
      replaced_by_id: 6,
      created_at: new Date(),
    });
    await expect(svc.refresh(gen.token)).rejects.toMatchObject({ code: 'invalid_grant' });
    expect(tokens.revokeAllRefreshTokensForUser).toHaveBeenCalledWith(42);
  });

  it('rejects unknown refresh token', async () => {
    const { svc, tokens } = await load();
    (tokens.findRefreshTokenByHash as any).mockResolvedValue(null);
    await expect(svc.refresh('bogus')).rejects.toMatchObject({ code: 'invalid_grant' });
  });

  it('rejects expired refresh token', async () => {
    const { svc, tokens } = await load();
    const tokenSvc = await import('../../src/services/tokenService.js');
    const gen = tokenSvc.generateRefreshToken();
    (tokens.findRefreshTokenByHash as any).mockResolvedValue({
      id_token: 5,
      id_user: 42,
      token_hash: gen.hash,
      expires_at: new Date(Date.now() - 1000),
      revoked_at: null,
      replaced_by_id: null,
      created_at: new Date(),
    });
    await expect(svc.refresh(gen.token)).rejects.toMatchObject({ code: 'invalid_grant' });
  });
});

describe('logout', () => {
  it('revokes an existing token', async () => {
    const { svc, tokens } = await load();
    (tokens.findRefreshTokenByHash as any).mockResolvedValue({
      id_token: 5, id_user: 42, token_hash: 'x', expires_at: new Date(Date.now() + 1000),
      revoked_at: null, replaced_by_id: null, created_at: new Date(),
    });
    await svc.logout('sometoken');
    expect(tokens.revokeRefreshToken).toHaveBeenCalledWith(5, null);
  });

  it('is idempotent for unknown token', async () => {
    const { svc, tokens } = await load();
    (tokens.findRefreshTokenByHash as any).mockResolvedValue(null);
    await expect(svc.logout('bogus')).resolves.toBeUndefined();
    expect(tokens.revokeRefreshToken).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/services/authService.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Create `src/services/authService.ts`**

```ts
import { AppError } from '../lib/errors.js';
import { verifyPassword } from './passwordService.js';
import {
  signAccessToken,
  generateRefreshToken,
  hashRefreshToken,
} from './tokenService.js';
import {
  findUserByUsername,
  findUserById,
  UserRow,
} from '../db/queries/userQueries.js';
import {
  insertRefreshToken,
  findRefreshTokenByHash,
  revokeRefreshToken,
  revokeAllRefreshTokensForUser,
} from '../db/queries/refreshTokenQueries.js';

const ACCESS_TTL_SECONDS = 900;

export interface PublicUser {
  id: number;
  username: string;
  role: 'admin' | 'learner';
  session: 'AM' | 'PM';
  first_name: string | null;
  last_name: string | null;
  email: string;
}

export interface AuthResult {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
}

export interface LoginResult extends AuthResult {
  user: PublicUser;
}

function toPublicUser(row: UserRow): PublicUser {
  return {
    id: row.id_user,
    username: row.username,
    role: row.role,
    session: row.session,
    first_name: row.first_name,
    last_name: row.last_name,
    email: row.email,
  };
}

async function issueTokensFor(user: UserRow): Promise<AuthResult> {
  const accessToken = signAccessToken({
    sub: user.id_user,
    role: user.role,
    session: user.role === 'learner' ? user.session : undefined,
  });
  const rt = generateRefreshToken();
  await insertRefreshToken({
    userId: user.id_user,
    tokenHash: rt.hash,
    expiresAt: rt.expiresAt,
  });
  return {
    accessToken,
    refreshToken: rt.token,
    expiresIn: ACCESS_TTL_SECONDS,
  };
}

export async function login(username: string, password: string): Promise<LoginResult> {
  const user = await findUserByUsername(username);
  if (!user) throw new AppError('invalid_credentials');
  const ok = await verifyPassword(password, user.password);
  if (!ok) throw new AppError('invalid_credentials');
  const tokens = await issueTokensFor(user);
  return { ...tokens, user: toPublicUser(user) };
}

export async function refresh(refreshToken: string): Promise<AuthResult> {
  const hash = hashRefreshToken(refreshToken);
  const row = await findRefreshTokenByHash(hash);
  if (!row) throw new AppError('invalid_grant');

  if (row.revoked_at !== null) {
    // Reuse detected — cascade revoke and reject.
    await revokeAllRefreshTokensForUser(row.id_user);
    throw new AppError('invalid_grant');
  }
  if (row.expires_at.getTime() <= Date.now()) {
    throw new AppError('invalid_grant');
  }

  const user = await findUserById(row.id_user);
  if (!user) throw new AppError('invalid_grant');

  const accessToken = signAccessToken({
    sub: user.id_user,
    role: user.role,
    session: user.role === 'learner' ? user.session : undefined,
  });
  const nextRt = generateRefreshToken();
  const newId = await insertRefreshToken({
    userId: user.id_user,
    tokenHash: nextRt.hash,
    expiresAt: nextRt.expiresAt,
  });
  await revokeRefreshToken(row.id_token, newId);

  return {
    accessToken,
    refreshToken: nextRt.token,
    expiresIn: ACCESS_TTL_SECONDS,
  };
}

export async function logout(refreshToken: string): Promise<void> {
  const hash = hashRefreshToken(refreshToken);
  const row = await findRefreshTokenByHash(hash);
  if (!row || row.revoked_at !== null) return;
  await revokeRefreshToken(row.id_token, null);
}
```

- [ ] **Step 4: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/services/authService.test.ts`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add src/services/authService.ts tests/services/authService.test.ts
git commit -m "feat(auth): add login, refresh, and logout service"
```

---

## Task 8: `requireAuth` middleware

**Files:**
- Create: `Aegis-Backend/src/middleware/requireAuth.ts`
- Create: `Aegis-Backend/tests/middleware/requireAuth.test.ts`

**Interfaces:**
- Consumes: `verifyAccessToken`, `AccessTokenClaims` from `tokenService`; `AppError` from `errors`
- Produces:
  - `interface AuthUser { id: number; role: 'admin' | 'learner'; session?: 'AM' | 'PM' }`
  - Express `Request` augmentation adds `user?: AuthUser`
  - `function requireAuth(req: Request, res: Response, next: NextFunction): void`

- [ ] **Step 1: Write failing test `tests/middleware/requireAuth.test.ts`**

```ts
import { describe, it, expect, vi, beforeAll } from 'vitest';
import type { Request, Response, NextFunction } from 'express';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

const load = async () => {
  const mw = await import('../../src/middleware/requireAuth.js');
  const tokens = await import('../../src/services/tokenService.js');
  return { mw, tokens };
};

function mockRes() {
  return {} as Response;
}

describe('requireAuth', () => {
  it('attaches user for a valid Bearer token', async () => {
    const { mw, tokens } = await load();
    const token = tokens.signAccessToken({ sub: 42, role: 'learner', session: 'AM' });
    const req = { headers: { authorization: `Bearer ${token}` } } as unknown as Request;
    const next = vi.fn() as unknown as NextFunction;
    mw.requireAuth(req, mockRes(), next);
    expect((req as any).user).toEqual({ id: 42, role: 'learner', session: 'AM' });
    expect(next).toHaveBeenCalledWith();
  });

  it('calls next with unauthorized error when header missing', async () => {
    const { mw } = await load();
    const req = { headers: {} } as unknown as Request;
    const next = vi.fn() as unknown as NextFunction;
    mw.requireAuth(req, mockRes(), next);
    const err = (next as any).mock.calls[0][0];
    expect(err.code).toBe('unauthorized');
  });

  it('calls next with unauthorized error when token invalid', async () => {
    const { mw } = await load();
    const req = { headers: { authorization: 'Bearer bogus' } } as unknown as Request;
    const next = vi.fn() as unknown as NextFunction;
    mw.requireAuth(req, mockRes(), next);
    const err = (next as any).mock.calls[0][0];
    expect(err.code).toBe('unauthorized');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/middleware/requireAuth.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Create `src/middleware/requireAuth.ts`**

```ts
import type { Request, Response, NextFunction } from 'express';
import { AppError } from '../lib/errors.js';
import { verifyAccessToken } from '../services/tokenService.js';

export interface AuthUser {
  id: number;
  role: 'admin' | 'learner';
  session?: 'AM' | 'PM';
}

declare module 'express-serve-static-core' {
  interface Request {
    user?: AuthUser;
  }
}

export function requireAuth(req: Request, _res: Response, next: NextFunction): void {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    return next(new AppError('unauthorized'));
  }
  const token = header.slice('Bearer '.length).trim();
  try {
    const claims = verifyAccessToken(token);
    req.user = {
      id: claims.sub,
      role: claims.role,
      session: claims.session,
    };
    next();
  } catch (err) {
    next(err);
  }
}
```

- [ ] **Step 4: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/middleware/requireAuth.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/middleware/requireAuth.ts tests/middleware/requireAuth.test.ts
git commit -m "feat(auth): add requireAuth middleware"
```

---

## Task 9: `requireRole` middleware

**Files:**
- Create: `Aegis-Backend/src/middleware/requireRole.ts`
- Create: `Aegis-Backend/tests/middleware/requireRole.test.ts`

**Interfaces:**
- Consumes: `AuthUser` from `requireAuth`; `AppError` from `errors`
- Produces: `function requireRole(role: 'admin' | 'learner'): RequestHandler`

- [ ] **Step 1: Write failing test `tests/middleware/requireRole.test.ts`**

```ts
import { describe, it, expect, vi, beforeAll } from 'vitest';
import type { Request, Response, NextFunction } from 'express';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

const load = () => import('../../src/middleware/requireRole.js');

describe('requireRole', () => {
  it('passes when role matches', async () => {
    const { requireRole } = await load();
    const req = { user: { id: 1, role: 'admin' as const } } as unknown as Request;
    const next = vi.fn() as unknown as NextFunction;
    requireRole('admin')(req, {} as Response, next);
    expect(next).toHaveBeenCalledWith();
  });

  it('rejects with forbidden when role mismatches', async () => {
    const { requireRole } = await load();
    const req = { user: { id: 1, role: 'learner' as const } } as unknown as Request;
    const next = vi.fn() as unknown as NextFunction;
    requireRole('admin')(req, {} as Response, next);
    const err = (next as any).mock.calls[0][0];
    expect(err.code).toBe('forbidden');
  });

  it('rejects with unauthorized when no user attached', async () => {
    const { requireRole } = await load();
    const req = {} as Request;
    const next = vi.fn() as unknown as NextFunction;
    requireRole('admin')(req, {} as Response, next);
    const err = (next as any).mock.calls[0][0];
    expect(err.code).toBe('unauthorized');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/middleware/requireRole.test.ts`
Expected: FAIL.

- [ ] **Step 3: Create `src/middleware/requireRole.ts`**

```ts
import type { RequestHandler } from 'express';
import { AppError } from '../lib/errors.js';

export function requireRole(role: 'admin' | 'learner'): RequestHandler {
  return (req, _res, next) => {
    if (!req.user) return next(new AppError('unauthorized'));
    if (req.user.role !== role) return next(new AppError('forbidden'));
    next();
  };
}
```

- [ ] **Step 4: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/middleware/requireRole.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/middleware/requireRole.ts tests/middleware/requireRole.test.ts
git commit -m "feat(auth): add requireRole middleware"
```

---

## Task 10: Rate limit and error-handler middleware

**Files:**
- Create: `Aegis-Backend/src/middleware/rateLimit.ts`
- Create: `Aegis-Backend/src/middleware/errorHandler.ts`

**Interfaces:**
- Consumes: `AppError` from `errors`, `logger`
- Produces:
  - `authRateLimit: RequestHandler` — 5 failed requests per (ip+username) per 15min → 429; skips 2xx responses
  - `function errorHandler(err, req, res, next): void` — translates `AppError` to `{ error, message }` JSON with correct status; falls through to 500 for unknown errors

- [ ] **Step 1: Create `src/middleware/rateLimit.ts`**

```ts
import rateLimit from 'express-rate-limit';
import type { Request } from 'express';

function keyFor(req: Request): string {
  const ip = req.ip ?? 'unknown';
  const username = typeof req.body?.username === 'string' ? req.body.username : '';
  return `${ip}:${username}`;
}

export const authRateLimit = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: keyFor,
  skipSuccessfulRequests: true,
  message: { error: 'too_many_requests', message: 'Too many requests — please try again later' },
});
```

- [ ] **Step 2: Create `src/middleware/errorHandler.ts`**

```ts
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
```

- [ ] **Step 3: Type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add src/middleware/rateLimit.ts src/middleware/errorHandler.ts
git commit -m "feat(http): add rate limit and error-handler middleware"
```

Note: `rateLimit` and `errorHandler` are exercised end-to-end in the route tests in Task 11.

---

## Task 11: Auth routes + app factory + supertest coverage

**Files:**
- Create: `Aegis-Backend/src/routes/auth.ts`
- Create: `Aegis-Backend/src/app.ts`
- Create: `Aegis-Backend/tests/routes/auth.test.ts`

**Interfaces:**
- Consumes: `login`, `refresh`, `logout` from `authService`; `authRateLimit`; `errorHandler`; `AppError`
- Produces:
  - `function buildApp(): express.Express` — assembled app with routes and error handler
  - Exported router `authRouter` mounted at `/auth`

- [ ] **Step 1: Write failing test `tests/routes/auth.test.ts`**

```ts
import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';
import request from 'supertest';

beforeAll(() => {
  process.env.JWT_SECRET = 'x'.repeat(64);
  process.env.DB_HOST = 'localhost';
  process.env.DB_PORT = '3306';
  process.env.DB_USER = 'u';
  process.env.DB_PASSWORD = 'p';
  process.env.DB_NAME = 'AEGIS';
});

vi.mock('../../src/services/authService.js', () => ({
  login: vi.fn(),
  refresh: vi.fn(),
  logout: vi.fn(),
}));

const load = async () => {
  const app = (await import('../../src/app.js')).buildApp();
  const svc = await import('../../src/services/authService.js');
  const { AppError } = await import('../../src/lib/errors.js');
  return { app, svc, AppError };
};

beforeEach(() => vi.clearAllMocks());

describe('POST /auth/login', () => {
  it('returns 200 with tokens on success', async () => {
    const { app, svc } = await load();
    (svc.login as any).mockResolvedValue({
      accessToken: 'a', refreshToken: 'r', expiresIn: 900,
      user: { id: 1, username: 'alice', role: 'learner', session: 'AM', first_name: null, last_name: null, email: 'a@x' },
    });
    const res = await request(app)
      .post('/auth/login')
      .send({ username: 'alice', password: 'hunter2' });
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({
      access_token: 'a',
      refresh_token: 'r',
      expires_in: 900,
      user: { id: 1, role: 'learner' },
    });
  });

  it('returns 400 on missing password', async () => {
    const { app } = await load();
    const res = await request(app).post('/auth/login').send({ username: 'a' });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe('invalid_request');
  });

  it('returns 401 on invalid credentials', async () => {
    const { app, svc, AppError } = await load();
    (svc.login as any).mockRejectedValue(new AppError('invalid_credentials'));
    const res = await request(app)
      .post('/auth/login')
      .send({ username: 'alice', password: 'wrong' });
    expect(res.status).toBe(401);
    expect(res.body.error).toBe('invalid_credentials');
  });
});

describe('POST /auth/refresh', () => {
  it('returns 200 with new tokens', async () => {
    const { app, svc } = await load();
    (svc.refresh as any).mockResolvedValue({
      accessToken: 'a2', refreshToken: 'r2', expiresIn: 900,
    });
    const res = await request(app).post('/auth/refresh').send({ refresh_token: 'r1' });
    expect(res.status).toBe(200);
    expect(res.body.access_token).toBe('a2');
  });

  it('returns 401 on invalid_grant', async () => {
    const { app, svc, AppError } = await load();
    (svc.refresh as any).mockRejectedValue(new AppError('invalid_grant'));
    const res = await request(app).post('/auth/refresh').send({ refresh_token: 'bogus' });
    expect(res.status).toBe(401);
    expect(res.body.error).toBe('invalid_grant');
  });

  it('returns 400 when refresh_token missing', async () => {
    const { app } = await load();
    const res = await request(app).post('/auth/refresh').send({});
    expect(res.status).toBe(400);
  });
});

describe('POST /auth/logout', () => {
  it('returns 204', async () => {
    const { app, svc } = await load();
    (svc.logout as any).mockResolvedValue(undefined);
    const res = await request(app).post('/auth/logout').send({ refresh_token: 'r' });
    expect(res.status).toBe(204);
    expect(svc.logout).toHaveBeenCalledWith('r');
  });

  it('returns 400 when refresh_token missing', async () => {
    const { app } = await load();
    const res = await request(app).post('/auth/logout').send({});
    expect(res.status).toBe(400);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Aegis-Backend && npm test -- tests/routes/auth.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Create `src/routes/auth.ts`**

```ts
import { Router } from 'express';
import { z } from 'zod';
import { AppError } from '../lib/errors.js';
import { login, refresh, logout } from '../services/authService.js';
import { authRateLimit } from '../middleware/rateLimit.js';

const loginSchema = z.object({
  username: z.string().min(1).max(50),
  password: z.string().min(1).max(200),
});

const refreshSchema = z.object({
  refresh_token: z.string().min(1),
});

const logoutSchema = z.object({
  refresh_token: z.string().min(1),
});

export const authRouter = Router();

authRouter.post('/login', authRateLimit, async (req, res, next) => {
  const parsed = loginSchema.safeParse(req.body);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    const result = await login(parsed.data.username, parsed.data.password);
    res.status(200).json({
      access_token: result.accessToken,
      refresh_token: result.refreshToken,
      expires_in: result.expiresIn,
      user: result.user,
    });
  } catch (err) {
    next(err);
  }
});

authRouter.post('/refresh', authRateLimit, async (req, res, next) => {
  const parsed = refreshSchema.safeParse(req.body);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    const result = await refresh(parsed.data.refresh_token);
    res.status(200).json({
      access_token: result.accessToken,
      refresh_token: result.refreshToken,
      expires_in: result.expiresIn,
    });
  } catch (err) {
    next(err);
  }
});

authRouter.post('/logout', async (req, res, next) => {
  const parsed = logoutSchema.safeParse(req.body);
  if (!parsed.success) return next(new AppError('invalid_request'));
  try {
    await logout(parsed.data.refresh_token);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});
```

- [ ] **Step 4: Create `src/app.ts`**

```ts
import express from 'express';
import { authRouter } from './routes/auth.js';
import { errorHandler } from './middleware/errorHandler.js';

export function buildApp(): express.Express {
  const app = express();
  app.use(express.json({ limit: '64kb' }));
  app.get('/health', (_req, res) => {
    res.json({ status: 'ok' });
  });
  app.use('/auth', authRouter);
  app.use(errorHandler);
  return app;
}
```

- [ ] **Step 5: Run tests**

Run: `cd Aegis-Backend && npm test -- tests/routes/auth.test.ts`
Expected: PASS (8 tests).

- [ ] **Step 6: Run full test suite**

Run: `cd Aegis-Backend && npm test`
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add src/routes/auth.ts src/app.ts tests/routes/auth.test.ts
git commit -m "feat(auth): wire login/refresh/logout routes and app factory"
```

---

## Task 12: Server boot + seed script

**Files:**
- Create: `Aegis-Backend/src/server.ts`
- Create: `Aegis-Backend/scripts/seed.ts`

**Interfaces:**
- Consumes: `buildApp` from `app`; `config`; `logger`; `hashPassword`; `findUserByUsername`, `insertUser` from `userQueries`
- Produces: `npm start`, `npm run dev`, `npm run seed` all work

- [ ] **Step 1: Create `src/server.ts`**

```ts
import { buildApp } from './app.js';
import { config } from './lib/config.js';
import { logger } from './lib/logger.js';

const app = buildApp();
app.listen(config.port, () => {
  logger.info({ port: config.port }, 'Aegis backend listening');
});
```

- [ ] **Step 2: Create `scripts/seed.ts`**

```ts
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
```

- [ ] **Step 3: Type-check**

Run: `cd Aegis-Backend && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 4: Full lint pass**

Run: `cd Aegis-Backend && npm run lint`
Expected: exit 0.

- [ ] **Step 5: Full test suite**

Run: `cd Aegis-Backend && npm test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/server.ts scripts/seed.ts
git commit -m "feat(auth): add server boot entry and admin seed script"
```

---

## Verification checklist (post-implementation)

Once all 12 tasks land, this holds true:

- `npm test` passes with 0 failures. Suites: config, passwordService, tokenService, authService, requireAuth, requireRole, routes/auth.
- `npm run build` compiles cleanly.
- `npm run migrate` applied against an empty MySQL creates AEGIS DB, all four base tables, plus `REFRESH_TOKEN` and `SCHEMA_MIGRATIONS`.
- `npm run seed` creates the admin user (idempotent on re-run).
- `npm run dev` boots and `GET /health` returns `{"status":"ok"}`.
- `POST /auth/login` with seeded admin credentials returns access + refresh tokens.
- `POST /auth/refresh` with that refresh token returns a new pair; presenting the old refresh a second time returns 401 and revokes all user tokens.
- `POST /auth/logout` returns 204; subsequent `POST /auth/refresh` with the logged-out token returns 401.
- Rate limit: 6 rapid failing logins from the same IP+username return 429 on the 6th.
