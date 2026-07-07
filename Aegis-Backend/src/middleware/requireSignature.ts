import type { RequestHandler } from 'express';
import { createHash, createVerify } from 'node:crypto';
import { AppError } from '../lib/errors.js';
import { x963ToSpkiDer } from '../lib/deviceKey.js';
import { findUserById } from '../db/queries/userQueries.js';

const CLOCK_SKEW_MS = 60_000; // ±60 seconds

export const requireSignature: RequestHandler = async (req, _res, next) => {
  try {
    if (!req.user) return next(new AppError('unauthorized'));

    const tsHeader = req.headers['x-timestamp'];
    const sigHeader = req.headers['x-signature'];
    if (typeof tsHeader !== 'string' || typeof sigHeader !== 'string') {
      return next(new AppError('invalid_request', 'Missing X-Timestamp or X-Signature header'));
    }

    // 1. Timestamp freshness
    const timestamp = parseInt(tsHeader, 10);
    if (Number.isNaN(timestamp)) {
      return next(new AppError('invalid_request', 'X-Timestamp must be a Unix epoch integer'));
    }
    if (Math.abs(Date.now() - timestamp * 1000) > CLOCK_SKEW_MS) {
      return next(new AppError('invalid_request', 'Request timestamp is too old or too far in the future'));
    }

    // 2. Stored public key
    const user = await findUserById(req.user.id);
    if (!user?.device_public_key) {
      return next(new AppError('forbidden', 'No device registered for this account'));
    }

    // 3. Rebuild canonical payload. Use originalUrl (with query stripped)
    //    because req.path is relative to the router mount point.
    const path = req.originalUrl.split('?')[0];
    const rawBody: Buffer = (req as unknown as { rawBody?: Buffer }).rawBody ?? Buffer.alloc(0);
    const bodyHash = createHash('sha256').update(rawBody).digest('hex');
    const payload = `${req.method}\n${path}\n${timestamp}\n${bodyHash}`;

    // 4. Verify (wrap the raw X9.63 point into SPKI DER first)
    const spkiDer = x963ToSpkiDer(Buffer.from(user.device_public_key, 'base64'));
    const signatureDer = Buffer.from(sigHeader, 'base64');
    const verifier = createVerify('SHA256');
    verifier.update(payload);
    const valid = verifier.verify(
      { key: spkiDer, format: 'der', type: 'spki', dsaEncoding: 'der' },
      signatureDer,
    );
    if (!valid) return next(new AppError('forbidden', 'Invalid device signature'));

    next();
  } catch (err) {
    next(err);
  }
};
