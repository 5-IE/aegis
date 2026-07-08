import { AppError } from './errors.js';

// Fixed ASN.1 prefix for a P-256 (prime256v1) SubjectPublicKeyInfo whose
// BIT STRING holds a 65-byte uncompressed X9.63 point. Prepending this to the
// raw point yields a 91-byte SPKI DER key that Node's crypto can import.
const P256_SPKI_HEADER = Buffer.from(
  '3059301306072a8648ce3d020106082a8648ce3d030107034200',
  'hex',
);

/**
 * Wrap a raw X9.63 uncompressed P-256 public point (as produced by iOS
 * CryptoKit `publicKey.x963Representation`) into SPKI DER.
 */
export function x963ToSpkiDer(rawX963: Buffer): Buffer {
  if (rawX963.length !== 65 || rawX963[0] !== 0x04) {
    throw new AppError('forbidden', 'Malformed device public key');
  }
  return Buffer.concat([P256_SPKI_HEADER, rawX963]);
}
