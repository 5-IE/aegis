import type { RequestHandler } from 'express';
import { createHash, createVerify } from 'node:crypto';
import { AppError } from '../lib/errors.js';
import { x963ToSpkiDer } from '../lib/deviceKey.js';
import { findUserById } from '../db/queries/userQueries.js';

const CLOCK_SKEW_MS = 60_000; // ±60 seconds
// NOTE: within this window a captured request can be replayed (no nonce cache).
// This is an accepted trade-off; presenceRateLimit (per-user) bounds the abuse.

export const requireSignature: RequestHandler = async (req, _res, next) => {
  try {
    if (!req.user) return next(new AppError('unauthorized'));

    const tsHeader = req.headers['x-timestamp'];
    const sigHeader = req.headers['x-signature'];
    if (typeof tsHeader !== 'string' || typeof sigHeader !== 'string') {
      return next(new AppError('invalid_request', 'Missing X-Timestamp or X-Signature header'));
    }

    // 1. Timestamp freshness. Require a strict non-negative integer string —
    //    parseInt is lenient (accepts "123abc", "17203e5.5", leading spaces).
    if (!/^\d+$/.test(tsHeader)) {
      return next(new AppError('invalid_request', 'X-Timestamp must be a Unix epoch integer'));
    }
    const timestamp = parseInt(tsHeader, 10);
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

    // 4. Verify (wrap the raw X9.63 point into SPKI DER first).
    //    A garbage/off-curve stored key makes createVerify.verify() THROW
    //    (ERR_OSSL_EVP_DECODE_ERROR); a merely wrong or malformed signature
    //    returns false. Both mean the caller cannot prove the device — treat as
    //    403, not a 500. (AppError from x963ToSpkiDer is re-raised unchanged.)
    let valid: boolean;
    try {
      const spkiDer = x963ToSpkiDer(Buffer.from(user.device_public_key, 'base64'));
      const signatureDer = Buffer.from(sigHeader, 'base64');
      const verifier = createVerify('SHA256');
      verifier.update(payload);
      valid = verifier.verify(
        { key: spkiDer, format: 'der', type: 'spki', dsaEncoding: 'der' },
        signatureDer,
      );
    } catch (verifyErr) {
      if (verifyErr instanceof AppError) return next(verifyErr);
      return next(new AppError('forbidden', 'Invalid device signature'));
    }
    if (!valid) return next(new AppError('forbidden', 'Invalid device signature'));

    next();
  } catch (err) {
    next(err);
  }
};
