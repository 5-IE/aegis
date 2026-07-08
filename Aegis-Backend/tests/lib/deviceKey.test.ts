import { describe, it, expect } from 'vitest';
import { generateKeyPairSync, createPublicKey } from 'node:crypto';
import { x963ToSpkiDer } from '../../src/lib/deviceKey.js';

// Extract the 65-byte raw X9.63 point from a generated P-256 key by slicing
// the 26-byte header off its SPKI DER export.
function rawPoint(): { raw: Buffer; spki: Buffer } {
  const { publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const spki = publicKey.export({ format: 'der', type: 'spki' }) as Buffer;
  return { raw: spki.subarray(26), spki };
}

describe('x963ToSpkiDer', () => {
  it('reconstructs a valid SPKI DER that Node can import', () => {
    const { raw, spki } = rawPoint();
    const rebuilt = x963ToSpkiDer(raw);
    expect(rebuilt.equals(spki)).toBe(true);
    // Node must accept the rebuilt key
    expect(() => createPublicKey({ key: rebuilt, format: 'der', type: 'spki' })).not.toThrow();
  });

  it('rejects a point of the wrong length', () => {
    expect(() => x963ToSpkiDer(Buffer.alloc(64, 4))).toThrowError(/Malformed/);
  });

  it('rejects a point with the wrong leading byte', () => {
    const bad = Buffer.alloc(65, 0);
    bad[0] = 0x03; // compressed marker, not uncompressed
    expect(() => x963ToSpkiDer(bad)).toThrowError(/Malformed/);
  });

  it('wraps a shape-valid but off-curve point (curve check is deferred to crypto)', () => {
    // x963ToSpkiDer only validates length + leading byte, NOT curve membership.
    // An all-0xff point has the right shape but is not on P-256, so the wrap
    // succeeds while Node's crypto rejects it downstream.
    const offCurve = Buffer.alloc(65, 0xff);
    offCurve[0] = 0x04;
    const spki = x963ToSpkiDer(offCurve);
    expect(spki.length).toBe(91);
    expect(() => createPublicKey({ key: spki, format: 'der', type: 'spki' })).toThrow();
  });
});
