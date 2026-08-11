import Foundation

/// SPEC.md §9.1 categories — metadata for icons/suggestions, and (per later
/// product direction) an optional manual pick + display grouping in Home.
/// Still never a folder in the storage sense: every item lives in one flat
/// store regardless of category, grouping is purely a Home display mode.
/// Shared with LifeVarsWidgets so the Pinned Variable widget can show a
/// category icon without ever learning the pinned item's name (§19.4).
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

    /// Same informal per-category emoji already used as shorthand in
    /// Classification.swift's rule table comments and SPEC.md §9.1 — reused
    /// here for real, on the Pinned Variable widget (§19.4), where a
    /// category hint is the deliberate ceiling: enough to glance-recognize
    /// which pin it is, never enough to reveal the actual name.
    var emoji: String {
        switch self {
        case .identity: return "\u{1FAAA}"
        case .vehicle: return "\u{1F697}"
        case .home: return "\u{1F3E0}"
        case .business: return "\u{1F3E2}"
        case .insurance: return "\u{271A}"
        case .financial: return "\u{1F4B0}"
        case .membership: return "\u{2705}"
        case .other: return "\u{1F3F7}\u{FE0F}"
        }
    }
}
