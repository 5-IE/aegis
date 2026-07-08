// Sentry instrumentation. This MUST be imported before any other module so the
// SDK can auto-instrument http/express/etc. See server.ts (first import).
//
// Disabled unless SENTRY_DSN is set — with no DSN, Sentry.init is a no-op and
// the app runs exactly as before.
import * as Sentry from '@sentry/node';
import { config } from './lib/config.js';

if (config.sentry.dsn) {
  Sentry.init({
    dsn: config.sentry.dsn,
    environment: config.sentry.environment,
    tracesSampleRate: config.sentry.tracesSampleRate,
  });
}

export { Sentry };
