import Foundation
import CryptoKit
import CommonCrypto

/// Plaintext transport shape for one QuickVar in a backup file — deliberately
/// its own type, not `QuickVarFields` + a value tacked on, so the on-disk
/// backup format doesn't silently drift whenever the app's internal model
/// changes shape. This is the only place outside `RevealView`/`revealValue()`
/// that a decrypted value ever exists, and only ever in memory, immediately
/// re-encrypted under a password before it touches disk.
struct BackupItem: Codable {
    var name: String
    var aliases: [String]
    var category: Category?
    var format: ValueFormat?
    var expiresAt: Date?
    var deleteOnExpiration: Bool
    var isEmergencyAccessible: Bool
    var isPinned: Bool
    var value: String
}

/// `salt`/`iterations` travel with the file itself (not secret — standard
/// PBKDF2 practice) so a future version can raise the iteration count
/// without breaking the ability to open backups written by an older one.
private struct BackupEnvelope: Codable {
    var version: Int
    var salt: Data
    var iterations: Int
    var ciphertext: Data
}

enum BackupError: Error {
    /// Deliberately one error for both cases — telling an attacker "the
    /// password was wrong" vs. "the file is corrupt" is free information
    /// a legitimate user restoring their own backup doesn't need split out.
    case wrongPasswordOrCorrupt
}

/// No account, no server (§ security invariants) — a backup file has to be
/// decryptable on a different device or after a reinstall, so it can't be
/// sealed under the device-only DEK the way everything else is. A
/// user-chosen password + PBKDF2 is the standard local-only answer.
enum BackupCodec {
    private static let currentVersion = 1
    private static let iterations = 300_000
    private static let saltLength = 16

    static func encrypt(items: [BackupItem], password: String) throws -> Data {
        var saltBytes = [UInt8](repeating: 0, count: saltLength)
        _ = SecRandomCopyBytes(kSecRandomDefault, saltLength, &saltBytes)
        let salt = Data(saltBytes)

        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        let plaintext = try JSONEncoder().encode(items)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw BackupError.wrongPasswordOrCorrupt }

        let envelope = BackupEnvelope(version: currentVersion, salt: salt, iterations: iterations, ciphertext: combined)
        return try JSONEncoder().encode(envelope)
    }

    static func decrypt(data: Data, password: String) throws -> [BackupItem] {
        let envelope: BackupEnvelope
        do {
            envelope = try JSONDecoder().decode(BackupEnvelope.self, from: data)
        } catch {
            throw BackupError.wrongPasswordOrCorrupt
        }
        let key = try deriveKey(password: password, salt: envelope.salt, iterations: envelope.iterations)
        do {
            let box = try AES.GCM.SealedBox(combined: envelope.ciphertext)
            let plaintext = try AES.GCM.open(box, using: key)
            return try JSONDecoder().decode([BackupItem].self, from: plaintext)
        } catch {
            throw BackupError.wrongPasswordOrCorrupt
        }
    }

    private static func deriveKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let keyLength = 32
        var derivedKeyData = Data(repeating: 0, count: keyLength)
        let status: Int32 = derivedKeyData.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                password.withCString { passwordCString in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordCString,
                        password.utf8.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw BackupError.wrongPasswordOrCorrupt }
        return SymmetricKey(data: derivedKeyData)
    }
}
