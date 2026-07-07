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
});
