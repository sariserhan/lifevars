import Foundation
import CryptoKit

/// SPEC.md §15.1 — AES-GCM via CryptoKit, one DEK for every encryptedMetadata
/// and encryptedValue blob. No custom crypto.
enum CryptoBoxError: Error {
    case sealFailed
    case invalidUTF8
}

enum CryptoBox {
    static func seal(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw CryptoBoxError.sealFailed }
        return combined
    }

    static func open(_ data: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }

    static func sealCodable<T: Encodable>(_ value: T, using key: SymmetricKey) throws -> Data {
        try seal(JSONEncoder().encode(value), using: key)
    }

    static func openCodable<T: Decodable>(_ data: Data, as type: T.Type, using key: SymmetricKey) throws -> T {
        try JSONDecoder().decode(T.self, from: try open(data, using: key))
    }
}
