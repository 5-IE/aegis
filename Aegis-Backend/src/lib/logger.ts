import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import pino from 'pino';
import { config } from './config.js';

const isProd = process.env.NODE_ENV === 'production';

// Build the destination(s). Always log to stdout (captured by journald in
// prod). When LOG_FILE is set, ALSO append newline-delimited JSON to that file
// so you can `tail -f` / `grep` it directly over SSH.
function buildDestination() {
  const streams: pino.StreamEntry[] = [{ stream: process.stdout }];

  if (config.logFile) {
    try {
      mkdirSync(dirname(config.logFile), { recursive: true });
    } catch {
      // directory may already exist / be unwritable — pino.destination will surface it
    }
    streams.push({
      // append, and sync so a crash still flushes recent lines
      stream: pino.destination({ dest: config.logFile, append: true, sync: false, mkdir: true }),
    });
  }

  return pino.multistream(streams);
}

// Pretty output only in non-prod AND when not writing to a file (pino-pretty
// transports don't compose with multistream). File/prod always gets JSON.
const usePretty = !isProd && !config.logFile;

export const logger = usePretty
  ? pino({
      level: config.logLevel,
      transport: { target: 'pino-pretty', options: { colorize: true } },
    })
  : pino({ level: config.logLevel }, buildDestination());
