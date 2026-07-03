//
//  CryptoManager.swift
//  Aegis
//
//  Created by Steve Agustinus on 03/07/26.
//

import Foundation
class CryptoManager {
    static let shared = CryptoManager()
    
    private let keyTag = "com.academytracker.devicekey".data(using: .utf8)!
    
    func generateDeviceKeyPair() -> SecKey? {
        guard let accessControl = SecAccessControlCreateWithFlags(kCFAllocatorDefault, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage], nil) else { return nil }
        
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String : keyTag,
                kSecAttrAccessControl as String: accessControl
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            print("Error generating key: \(error!.takeRetainedValue() as Error)")
            return nil
        }
        
        return privateKey
    }
    
    func getPublicKeyBase64() -> String? {
        guard let privateKey = loadPrivateKey(),
              let publicKey = SecKeyCopyPublicKey(privateKey) else { return nil }
        
        var error: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else { return nil }
        
        return keyData.base64EncodedString()
    }
    
    func loadPrivateKey() -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess else { return nil }
        return (item as! SecKey)
    }
    
    func sign(serverChallenge: String) -> String? {
        guard let privateKey = loadPrivateKey(),
              let challengeData = serverChallenge.data(using: .utf8) else {
            return nil
        }
        
        let algorithm: SecKeyAlgorithm = .ecdsaSignatureMessageX962SHA256
        
        guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else { return nil }
        
        var error: Unmanaged<CFError>?
        guard let signatureData = SecKeyCreateSignature(privateKey, algorithm, challengeData as CFData, &error) as Data? else {
            print("Signing failed: \(error!.takeRetainedValue() as Error)")
            return nil
        }
        
        return signatureData.base64EncodedString()
    }
}
