import Foundation
import SwiftData

/// SPEC.md §9.1 categories — metadata for icons/suggestions, and (per later
/// product direction) an optional manual pick + display grouping in Home.
/// Still never a folder in the storage sense: every item lives in one flat
/// store regardless of category, grouping is purely a Home display mode.
enum Category: String, Codable, CaseIterable, Hashable {
    case identity, vehicle, home, business, insurance, financial, membership, other

    var label: String { rawValue.capitalized }

    var symbolName: String {
        switch self {
        case .identity: return "person.text.rectangle.fill"
        case .vehicle: return "car.fill"
        case .home: return "house.fill"
        case .business: return "building.2.fill"
        case .insurance: return "cross.case.fill"
        case .financial: return "banknote.fill"
        case .membership: return "person.crop.circle.badge.checkmark"
        case .other: return "tag.fill"
        }
    }
}

/// Cosmetic display transform only — never changes the stored value. Derived
/// from Classification at Add time and carried in the encrypted metadata so
/// Reveal doesn't have to re-guess it from the name every time.
enum ValueFormat: String, Codable {
    case ssn
    case ein

    func apply(to value: String) -> String {
        let digits = value.filter(\.isNumber)
        guard digits.count == 9 else { return value }
        switch self {
        case .ssn:
            let a = digits.prefix(3)
            let b = digits.dropFirst(3).prefix(2)
            let c = digits.dropFirst(5)
            return "\(a)-\(b)-\(c)"
        case .ein:
            let a = digits.prefix(2)
            let b = digits.dropFirst(2)
            return "\(a)-\(b)"
        }
    }
}

/// SPEC.md §14 — serialized and encrypted together as LifeVar.encryptedMetadata.
/// Category is included so it never sits in plaintext next to a name that's
/// still encrypted (§17 in the source discussion). `isEmergencyAccessible` is
/// just a flag here — the actual emergency-readable copy lives separately in
/// `LifeVar.emergencyPayload`, sealed under a different, weaker-gated key
/// (Security/EmergencyKeyStore.swift), never under this record's normal DEK.
struct LifeVarMetadata: Codable {
    var name: String
    var aliases: [String]
    var category: Category?
    var format: ValueFormat?
    var expiresAt: Date?
    var deleteOnExpiration: Bool
    var isEmergencyAccessible: Bool
    var isPinned: Bool = false
}

/// SPEC.md §14 — on disk, nothing is plaintext except id and the date fields.
/// Persisted via SwiftData; the store file itself is excluded from device
/// backup (Persistence.swift, §15.2) since its ciphertext is unreadable
/// without the Keychain-sealed DEK, which never restores to a new device.
@Model
final class LifeVar {
    @Attribute(.unique) var id: UUID
    var encryptedMetadata: Data
    var encryptedValue: Data
    /// Present only when the user opted this item into Emergency Info —
    /// encrypted JSON `{name, value}` sealed under the emergency key
    /// (no biometric gate), so it's readable from the LockScreen without
    /// Face ID. `nil` for the overwhelming majority of items.
    var emergencyPayload: Data?
    var createdAt: Date
    var updatedAt: Date
    var lastAccessedAt: Date?

    init(
        id: UUID = UUID(),
        encryptedMetadata: Data,
        encryptedValue: Data,
        emergencyPayload: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastAccessedAt: Date? = nil
    ) {
        self.id = id
        self.encryptedMetadata = encryptedMetadata
        self.encryptedValue = encryptedValue
        self.emergencyPayload = emergencyPayload
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastAccessedAt = lastAccessedAt
    }
}
