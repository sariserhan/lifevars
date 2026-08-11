import Foundation
import Security
import LocalAuthentication
import CryptoKit

/// SPEC.md §15.1 — the entire auth mechanism lives here. Fetching the DEK from
/// Keychain (via an access-controlled item) *is* the Face ID/passcode prompt;
/// there is deliberately no separate LAContext.evaluatePolicy() call anywhere
/// else in the app. One key, one place it's protected, one way it's evaluated.
enum KeychainDEKError: Error {
    case biometryInvalidated
    case userCancelled
    case unavailable
    case unexpected(OSStatus)
}

final class KeychainDEKStore {
    private let account = "dek"
    private let service = "com.serhansari.QuickVars"

    /// Creates the DEK on first-ever call, otherwise fetches the existing one.
    /// The fetch is what triggers the system Face ID/passcode UI (§15.1) — the
    /// create-if-missing step below deliberately does not require auth, since
    /// SecItemAdd on a fresh item never prompts, only SecItemCopyMatching does.
    func fetchOrCreateDEK(context: LAContext) throws -> SymmetricKey {
        if let existing = try fetchDEK(context: context) {
            return existing
        }
        let newKey = SymmetricKey(size: .bits256)
        try storeDEK(newKey)
        guard let confirmed = try fetchDEK(context: context) else {
            throw KeychainDEKError.unavailable
        }
        return confirmed
    }

    private func storeDEK(_ key: SymmetricKey) throws {
        var accessError: Unmanaged<CFError>?
        // SPEC.md §2.4: .biometryCurrentSet (Face ID Only) has no passcode
        // fallback and is invalidated permanently by iOS if Face ID enrollment
        // changes. .userPresence (Face ID + Passcode) accepts either and
        // survives an enrollment change. This is the one place that decision
        // takes effect — do not add a second auth path elsewhere.
        let flags: SecAccessControlCreateFlags = UserSettings.unlockMethod == .faceIDOnly
            ? .biometryCurrentSet
            : .userPresence

        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            flags,
            &accessError
        ) else {
            throw KeychainDEKError.unavailable
        }

        let keyData = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrAccessControl as String: access
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainDEKError.unexpected(status)
        }
    }

    private func fetchDEK(context: LAContext) throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        case errSecUserCanceled:
            throw KeychainDEKError.userCancelled
        case errSecAuthFailed:
            throw KeychainDEKError.biometryInvalidated
        default:
            throw KeychainDEKError.unexpected(status)
        }
    }

    /// SPEC.md §15.2 — distinct, user-facing wording per failure mode instead
    /// of one generic "auth failed" retry loop.
    static func describeFailure(_ error: Error) -> String {
        switch error as? KeychainDEKError {
        case .userCancelled:
            return "Couldn't verify it's you."
        case .biometryInvalidated:
            return "Your device's Face ID settings changed. QuickVars data protected under Face ID Only cannot be recovered without a backup."
        default:
            return "Your encrypted data could not be accessed. This can happen if your device's security settings changed."
        }
    }
}
