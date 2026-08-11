import Foundation
import Security
import CryptoKit

/// A second key, deliberately weaker-gated than the main DEK — no biometric
/// or passcode access control at all, just `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
/// (standard "the device has been unlocked at least once since boot"
/// protection, the same class most apps' ordinary data lives under). This is
/// what makes Emergency Info readable from the LockScreen without Face ID —
/// mirroring the same disclosed trade-off Apple's own Medical ID makes for a
/// narrow, user-curated set of fields.
///
/// Only items the user explicitly opts in (QuickVar.emergencyPayload) ever
/// touch this key. Every other QuickVar is completely unaffected and stays
/// behind the real DEK (KeychainDEKStore) — this key can decrypt nothing
/// else.
enum EmergencyKeyStoreError: Error {
    case unavailable
}

final class EmergencyKeyStore {
    private let account = "emergency-key"
    private let service = "com.serhansari.QuickVars"

    func fetchOrCreateKey() throws -> SymmetricKey {
        if let existing = try fetchKey() {
            return existing
        }
        let newKey = SymmetricKey(size: .bits256)
        try storeKey(newKey)
        guard let confirmed = try fetchKey() else { throw EmergencyKeyStoreError.unavailable }
        return confirmed
    }

    private func storeKey(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw EmergencyKeyStoreError.unavailable }
    }

    private func fetchKey() throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw EmergencyKeyStoreError.unavailable
        }
    }
}
