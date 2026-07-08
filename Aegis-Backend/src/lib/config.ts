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
  // Optional: when set, every log line is also written to this file (in
  // addition to stdout/journal). e.g. LOG_FILE=/var/log/aegis/app.log
  logFile: process.env.LOG_FILE && process.env.LOG_FILE.length > 0 ? process.env.LOG_FILE : undefined,
  jwtSecret,
  db: {
    host: required('DB_HOST'),
    port: requiredInt('DB_PORT'),
    user: required('DB_USER'),
    password: required('DB_PASSWORD'),
    name: required('DB_NAME'),
  },
  sentry: {
    // Optional: set SENTRY_DSN to enable error monitoring. Empty = disabled.
    dsn: process.env.SENTRY_DSN && process.env.SENTRY_DSN.length > 0 ? process.env.SENTRY_DSN : undefined,
    environment: process.env.SENTRY_ENVIRONMENT ?? process.env.NODE_ENV ?? 'development',
    tracesSampleRate: Number.parseFloat(process.env.SENTRY_TRACES_SAMPLE_RATE ?? '0'),
  },
} as const;
