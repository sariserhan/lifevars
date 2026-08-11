import Foundation

/// The shadow copy sealed under the emergency key (EmergencyKeyStore) —
/// deliberately minimal, just what's needed to display the item. No
/// aliases, no format, no category; Emergency Info is a plain list, not a
/// second copy of the full app.
struct EmergencyPayload: Codable {
    var name: String
    var value: String
}
