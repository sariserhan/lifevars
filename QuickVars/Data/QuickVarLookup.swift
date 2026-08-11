import Foundation
import SwiftData
import CryptoKit

/// One-shot decrypt+match, independent of QuickVarStore/SessionManager's
/// persistent session state — used by CheckQuickVarIntent.swift, which runs
/// headless (no app UI, no `session.isUnlocked`) and does its own momentary
/// LAContext fetch per call. QuickVarStore.reload() builds the same shape of
/// decrypted index for a long-lived, already-unlocked session; this builds
/// it once for a single query and discards it.
enum QuickVarLookup {
    enum Result {
        case match(record: QuickVar, metadata: QuickVarMetadata)
        case ambiguous
        case notFound
    }

    static func lookup(query: String, dek: SymmetricKey, modelContext: ModelContext) -> Result {
        guard let records = try? modelContext.fetch(FetchDescriptor<QuickVar>()) else { return .notFound }

        let decrypted: [(record: QuickVar, metadata: QuickVarMetadata)] = records.compactMap { record in
            guard let metadata = try? CryptoBox.openCodable(record.encryptedMetadata, as: QuickVarMetadata.self, using: dek) else { return nil }
            return (record, metadata)
        }
        let entries = decrypted.map { DecryptedIndexEntry(id: $0.record.id, metadata: $0.metadata) }

        let matches = Matcher.match(query: query, in: entries)
        guard let topConfidence = matches.first?.confidence else { return .notFound }
        let topMatches = matches.filter { $0.confidence == topConfidence }
        guard topMatches.count == 1,
              let winner = decrypted.first(where: { $0.record.id == topMatches[0].entry.id }) else {
            return .ambiguous
        }
        return .match(record: winner.record, metadata: winner.metadata)
    }
}
