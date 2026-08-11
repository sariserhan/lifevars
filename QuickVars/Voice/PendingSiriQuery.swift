import Foundation

/// SPEC.md §13 — bridge between the App Intent and the running app. Holds
/// only raw query text, momentarily, in memory. Never a decrypted value —
/// the intent process structurally can't have one, since the DEK only ever
/// lives in memory inside an unlocked session (§15.1), which the intent
/// itself never establishes.
final class PendingSiriQuery {
    static let shared = PendingSiriQuery()
    private init() {}
    var query: String?
}
