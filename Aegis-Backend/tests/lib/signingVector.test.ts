import { describe, it, expect } from 'vitest';
import { createHash, createSign, createVerify, generateKeyPairSync } from 'node:crypto';
import { x963ToSpkiDer } from '../../src/lib/deviceKey.js';

// End-to-end vector: a known payload, signed with a fresh key, verifies through
// the same raw-point -> SPKI DER path the middleware uses. Locks the canonical
// payload construction and key-wrapping so the iOS and server sides cannot
// silently drift.
describe('signing vector', () => {
  it('body {"room_id":3} hashes to the documented value', () => {
    const hash = createHash('sha256').update(Buffer.from('{"room_id":3}')).digest('hex');
    // This exact value appears in docs/device-signing.md's worked example.
    expect(hash).toBe('7908b1690837f426aa17e210db69e2e5871630968643d69854db097f1a16d402');
  });

  it('sign-then-verify round-trips through x963ToSpkiDer', () => {
    const kp = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
    const spki = kp.publicKey.export({ format: 'der', type: 'spki' }) as Buffer;
    const rawPoint = spki.subarray(26); // what iOS sends (base64 of this)

    const timestamp = 1720300000;
    const bodyHash = createHash('sha256').update(Buffer.from('{"room_id":3}')).digest('hex');
    const payload = `POST\n/api/v1/presence\n${timestamp}\n${bodyHash}`;

    const signer = createSign('SHA256');
    signer.update(payload);
    const sig = signer.sign({ key: kp.privateKey, dsaEncoding: 'der' });

    const rebuilt = x963ToSpkiDer(rawPoint);
    const verifier = createVerify('SHA256');
    verifier.update(payload);
    const ok = verifier.verify({ key: rebuilt, format: 'der', type: 'spki', dsaEncoding: 'der' }, sig);
    expect(ok).toBe(true);
  });
});
