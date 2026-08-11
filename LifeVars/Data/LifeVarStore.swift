import Foundation
import SwiftData
import Combine
import CryptoKit

/// SPEC.md §15.1 — the in-memory index (names/aliases/category only, never
/// values) that Home/search read from. Populated by decrypting every record's
/// metadata once per unlock; cleared the moment the session locks.
struct DecryptedIndexEntry: Identifiable, Hashable {
    let id: UUID
    var name: String
    var aliases: [String]
    var category: Category?
    var format: ValueFormat?
    var expiresAt: Date?
    var deleteOnExpiration: Bool
    var isEmergencyAccessible: Bool
    var isPinned: Bool

    init(id: UUID, name: String, aliases: [String], category: Category?, format: ValueFormat?, expiresAt: Date?, deleteOnExpiration: Bool, isEmergencyAccessible: Bool, isPinned: Bool) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.category = category
        self.format = format
        self.expiresAt = expiresAt
        self.deleteOnExpiration = deleteOnExpiration
        self.isEmergencyAccessible = isEmergencyAccessible
        self.isPinned = isPinned
    }

    /// Shared by LifeVarStore.reload() (persistent session index) and
    /// LifeVarLookup (CheckLifeVarIntent's one-shot headless lookup) — one
    /// place translating decrypted metadata into this shape.
    init(id: UUID, metadata: LifeVarMetadata) {
        self.init(
            id: id,
            name: metadata.name,
            aliases: metadata.aliases,
            category: metadata.category,
            format: metadata.format,
            expiresAt: metadata.expiresAt,
            deleteOnExpiration: metadata.deleteOnExpiration,
            isEmergencyAccessible: metadata.isEmergencyAccessible,
            isPinned: metadata.isPinned
        )
    }
}

/// The full set of user-editable fields on a LifeVar, minus the value —
/// grouped so Add/Edit call sites don't pass eight positional arguments.
struct LifeVarFields {
    var name: String
    var aliases: [String]
    var category: Category?
    var format: ValueFormat?
    var expiresAt: Date?
    var deleteOnExpiration: Bool = false
    var isEmergencyAccessible: Bool = false
    var isPinned: Bool = false
}

enum LifeVarStoreError: Error {
    case locked
    case notFound
    case corrupt
}

@MainActor
final class LifeVarStore: ObservableObject {
    @Published private(set) var items: [DecryptedIndexEntry] = []

    private let modelContext: ModelContext
    private let session: SessionManager
    private let emergencyKeyStore = EmergencyKeyStore()
    private var cancellable: AnyCancellable?

    init(modelContext: ModelContext, session: SessionManager) {
        self.modelContext = modelContext
        self.session = session
        cancellable = session.$isUnlocked.sink { [weak self] unlocked in
            if unlocked {
                self?.reload()
            } else {
                // §15.1 — decrypted index discarded on lock.
                self?.items = []
            }
        }
    }

    func reload() {
        guard let dek = session.dek else {
            items = []
            return
        }
        guard var records = try? modelContext.fetch(FetchDescriptor<LifeVar>()) else {
            items = []
            return
        }

        if sweepExpiredTemporaryItems(records) {
            // Some records were just deleted — re-fetch rather than trust
            // the now-stale array.
            records = (try? modelContext.fetch(FetchDescriptor<LifeVar>())) ?? []
        }

        let decrypted: [(DecryptedIndexEntry, Date)] = records.compactMap { record in
            guard let metadata = try? CryptoBox.openCodable(record.encryptedMetadata, as: LifeVarMetadata.self, using: dek) else {
                return nil
            }
            let entry = DecryptedIndexEntry(id: record.id, metadata: metadata)
            return (entry, record.lastAccessedAt ?? record.createdAt)
        }
        // §3 — most-recently-accessed first; falls back to createdAt for never-revealed items.
        items = decrypted.sorted { $0.1 > $1.1 }.map(\.0)
        // Widgets/PinnedVariableWidget.swift reads this across the App Group
        // boundary — only ever an id, never the pinned item's name or value.
        WidgetBridge.pinnedItemID = items.first(where: \.isPinned)?.id
    }

    /// "hotel key code" case from the expiration metadata discussion: items
    /// marked delete-on-expiration quietly disappear the next time the app
    /// is opened after they expire — no server, no background task, just an
    /// opportunistic check on every unlock. Items that only *notify*
    /// (deleteOnExpiration == false) are left untouched here; that's
    /// ExpirationNotifier's job, on a schedule, independent of app launches.
    @discardableResult
    private func sweepExpiredTemporaryItems(_ records: [LifeVar]) -> Bool {
        guard let dek = session.dek else { return false }
        let now = Date()
        var didDelete = false
        for record in records {
            guard let metadata = try? CryptoBox.openCodable(record.encryptedMetadata, as: LifeVarMetadata.self, using: dek) else { continue }
            guard metadata.deleteOnExpiration, let expiresAt = metadata.expiresAt, expiresAt <= now else { continue }
            ExpirationNotifier.cancelReminder(for: record.id)
            modelContext.delete(record)
            didDelete = true
        }
        if didDelete {
            try? modelContext.save()
        }
        return didDelete
    }

    func nameExists(_ name: String, excluding excludeId: UUID? = nil) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return items.contains { entry in
            guard entry.id != excludeId else { return false }
            if entry.name.lowercased() == normalized { return true }
            return entry.aliases.contains { $0.lowercased() == normalized }
        }
    }

    func add(_ fields: LifeVarFields, value: String) throws {
        guard let dek = session.dek else { throw LifeVarStoreError.locked }
        let metadata = LifeVarMetadata(
            name: fields.name,
            aliases: fields.aliases,
            category: fields.category,
            format: fields.format,
            expiresAt: fields.expiresAt,
            deleteOnExpiration: fields.deleteOnExpiration,
            isEmergencyAccessible: fields.isEmergencyAccessible,
            isPinned: fields.isPinned
        )
        let record = LifeVar(
            encryptedMetadata: try CryptoBox.sealCodable(metadata, using: dek),
            encryptedValue: try CryptoBox.seal(Data(value.utf8), using: dek),
            emergencyPayload: try sealEmergencyPayloadIfNeeded(fields: fields, value: value)
        )
        modelContext.insert(record)
        try modelContext.save()
        if fields.isPinned {
            try unpinOtherRecords(except: record.id, dek: dek)
        }
        scheduleOrCancelReminder(id: record.id, fields: fields)
        reload()
    }

    func update(id: UUID, fields: LifeVarFields, value: String?) throws {
        guard let dek = session.dek else { throw LifeVarStoreError.locked }
        guard let record = try fetchRecord(id: id) else { throw LifeVarStoreError.notFound }

        let metadata = LifeVarMetadata(
            name: fields.name,
            aliases: fields.aliases,
            category: fields.category,
            format: fields.format,
            expiresAt: fields.expiresAt,
            deleteOnExpiration: fields.deleteOnExpiration,
            isEmergencyAccessible: fields.isEmergencyAccessible,
            isPinned: fields.isPinned
        )
        record.encryptedMetadata = try CryptoBox.sealCodable(metadata, using: dek)
        if let value {
            record.encryptedValue = try CryptoBox.seal(Data(value.utf8), using: dek)
        }

        if fields.isEmergencyAccessible {
            // Need the plaintext to build the shadow copy even if this edit
            // didn't change the value (or never revealed it) — decrypt with
            // the real DEK, which we already have since we're unlocked.
            let plaintext = try value ?? String(decoding: CryptoBox.open(record.encryptedValue, using: dek), as: UTF8.self)
            record.emergencyPayload = try sealEmergencyPayloadIfNeeded(fields: fields, value: plaintext)
        } else {
            record.emergencyPayload = nil
        }

        record.updatedAt = Date()
        try modelContext.save()
        if fields.isPinned {
            try unpinOtherRecords(except: id, dek: dek)
        }
        scheduleOrCancelReminder(id: id, fields: fields)
        reload()
    }

    func delete(id: UUID) throws {
        guard let record = try fetchRecord(id: id) else { return }
        ExpirationNotifier.cancelReminder(for: id)
        modelContext.delete(record)
        try modelContext.save()
        reload()
    }

    /// SPEC.md §15.1 — decrypts only the single requested record, never bulk.
    func revealValue(id: UUID) throws -> String {
        guard let dek = session.dek else { throw LifeVarStoreError.locked }
        guard let record = try fetchRecord(id: id) else { throw LifeVarStoreError.notFound }
        record.lastAccessedAt = Date()
        try modelContext.save()
        let opened = try CryptoBox.open(record.encryptedValue, using: dek)
        guard let string = String(data: opened, encoding: .utf8) else { throw LifeVarStoreError.corrupt }
        reload()
        return string
    }

    /// Deliberately independent of the normal session gate (§2) — this is
    /// the entire point of Emergency Info. Uses the separate, weaker-gated
    /// EmergencyKeyStore, never `session.dek`, so it works even when locked.
    func fetchEmergencyItems() -> [EmergencyPayload] {
        guard let records = try? modelContext.fetch(FetchDescriptor<LifeVar>()) else { return [] }
        guard let key = try? emergencyKeyStore.fetchOrCreateKey() else { return [] }
        return records.compactMap { record in
            guard let payload = record.emergencyPayload else { return nil }
            return try? CryptoBox.openCodable(payload, as: EmergencyPayload.self, using: key)
        }
    }

    private func sealEmergencyPayloadIfNeeded(fields: LifeVarFields, value: String) throws -> Data? {
        guard fields.isEmergencyAccessible else { return nil }
        let key = try emergencyKeyStore.fetchOrCreateKey()
        let payload = EmergencyPayload(name: fields.name, value: value)
        return try CryptoBox.sealCodable(payload, using: key)
    }

    /// Only one LifeVar can be pinned to the Lock Screen widget at a time —
    /// enforced here rather than in the UI, so it holds regardless of entry
    /// point (Add, Edit, or a future one).
    private func unpinOtherRecords(except exceptId: UUID, dek: SymmetricKey) throws {
        guard let records = try? modelContext.fetch(FetchDescriptor<LifeVar>()) else { return }
        for record in records where record.id != exceptId {
            guard var metadata = try? CryptoBox.openCodable(record.encryptedMetadata, as: LifeVarMetadata.self, using: dek) else { continue }
            guard metadata.isPinned else { continue }
            metadata.isPinned = false
            record.encryptedMetadata = try CryptoBox.sealCodable(metadata, using: dek)
        }
        try modelContext.save()
    }

    private func scheduleOrCancelReminder(id: UUID, fields: LifeVarFields) {
        if let expiresAt = fields.expiresAt, !fields.deleteOnExpiration {
            ExpirationNotifier.scheduleReminder(for: id, expiresAt: expiresAt)
        } else {
            ExpirationNotifier.cancelReminder(for: id)
        }
    }

    private func fetchRecord(id: UUID) throws -> LifeVar? {
        let descriptor = FetchDescriptor<LifeVar>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }
}
