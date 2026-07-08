//
//  CryptoManager.swift
//  Aegis
//
//  Created by Steve Agustinus on 03/07/26.
//

import CryptoKit
import Foundation
import Security

/// Device request signing with a P-256 key held in the Secure Enclave.
///
/// The private key's `dataRepresentation` is stored in the Keychain and
/// reloaded on launch (the raw key material never leaves the enclave — the
/// stored blob is an encrypted, enclave-bound reference). The public key is
/// exported as a raw X9.63 uncompressed point (base64); the server wraps it
/// into SPKI DER before verifying. See docs/device-signing.md.
///
/// On the simulator (and devices without a Secure Enclave) we fall back to a
/// plain in-process P-256 key so development builds still work.
final class CryptoManager {
    static let shared = CryptoManager()
    private init() {}

    private let keychainService = "com.academytracker.aegis"
    private let keychainAccount = "com.academytracker.devicekey"

    /// A P-256 signing key that may be enclave-backed or (fallback) in-process.
    private enum DeviceKey {
        case enclave(SecureEnclave.P256.Signing.PrivateKey)
        case software(P256.Signing.PrivateKey)

        var publicKeyX963: Data {
            switch self {
            case .enclave(let k): return k.publicKey.x963Representation
            case .software(let k): return k.publicKey.x963Representation
            }
        }

        func signature(for data: Data) throws -> P256.Signing.ECDSASignature {
            switch self {
            case .enclave(let k): return try k.signature(for: data)
            case .software(let k): return try k.signature(for: data)
            }
        }

        var storableRepresentation: Data {
            switch self {
            case .enclave(let k): return k.dataRepresentation
            case .software(let k): return k.dataRepresentation
            }
        }
    }

    // MARK: - Key lifecycle

    /// Load the persisted key, generating and storing one on first use.
    private func loadOrCreateKey() throws -> DeviceKey {
        if let data = readKeyData() {
            if SecureEnclave.isAvailable,
               let key = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data) {
                return .enclave(key)
            }
            if let key = try? P256.Signing.PrivateKey(dataRepresentation: data) {
                return .software(key)
            }
            // Stored blob is unusable (e.g. moved between enclave/software) —
            // fall through and generate a fresh key. The device must re-register.
        }

        let key: DeviceKey
        if SecureEnclave.isAvailable {
            key = .enclave(try SecureEnclave.P256.Signing.PrivateKey())
        } else {
            key = .software(P256.Signing.PrivateKey())
        }
        try storeKeyData(key.storableRepresentation)
        return key
    }

    /// Base64 of the raw X9.63 uncompressed public point — for /register-device.
    func publicKeyBase64() -> String? {
        guard let key = try? loadOrCreateKey() else { return nil }
        return key.publicKeyX963.base64EncodedString()
    }

    // MARK: - Signing

    /// Build the canonical payload, sign it, and return the header values.
    ///
    /// Payload: `METHOD\nPATH\nUNIX_TS\nSHA256_HEX(body)`. `path` must be the
    /// path the server signs against (e.g. `/api/v1/presence`) — no host, no
    /// query string. `body` must be the exact bytes sent as the request body
    /// (pass `Data()` for an empty body).
    func signRequest(
        method: String,
        path: String,
        body: Data
    ) throws -> (xTimestamp: String, xSignature: String) {
        let key = try loadOrCreateKey()
        let timestamp = Int(Date().timeIntervalSince1970)
        let bodyHashHex = SHA256.hash(data: body)
            .map { String(format: "%02x", $0) }
            .joined()
        let payload = "\(method)\n\(path)\n\(timestamp)\n\(bodyHashHex)"
        let signature = try key.signature(for: Data(payload.utf8))
        return (
            xTimestamp: String(timestamp),
            xSignature: signature.derRepresentation.base64EncodedString()
        )
    }

    // MARK: - Keychain (stores the key's dataRepresentation)

    private func readKeyData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func storeKeyData(_ data: Data) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(base as CFDictionary) // idempotent overwrite
        var attrs = base
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(
                domain: "CryptoManager",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to store device key: \(status)"]
            )
        }
    }
}
