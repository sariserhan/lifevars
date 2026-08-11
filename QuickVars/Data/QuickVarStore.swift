import Foundation
import SwiftData
import Combine
import CryptoKit
import WidgetKit

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

    /// Shared by QuickVarStore.reload() (persistent session index) and
    /// QuickVarLookup (CheckQuickVarIntent's one-shot headless lookup) — one
    /// place translating decrypted metadata into this shape.
    init(id: UUID, metadata: QuickVarMetadata) {
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

/// The full set of user-editable fields on a QuickVar, minus the value —
/// grouped so Add/Edit call sites don't pass eight positional arguments.
struct QuickVarFields {
    var name: String
    var aliases: [String]
    var category: Category?
    var format: ValueFormat?
    var expiresAt: Date?
    var deleteOnExpiration: Bool = false
    var isEmergencyAccessible: Bool = false
    var isPinned: Bool = false
}

enum QuickVarStoreError: Error {
    case locked
    case notFound
    case corrupt
}

@MainActor
final class QuickVarStore: ObservableObject {
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
        guard var records = try? modelContext.fetch(FetchDescriptor<QuickVar>()) else {
            items = []
            return
        }

        if sweepExpiredTemporaryItems(records) {
            // Some records were just deleted — re-fetch rather than trust
            // the now-stale array.
            records = (try? modelContext.fetch(FetchDescriptor<QuickVar>())) ?? []
        }

        let decrypted: [(DecryptedIndexEntry, Date)] = records.compactMap { record in
            guard let metadata = try? CryptoBox.openCodable(record.encryptedMetadata, as: QuickVarMetadata.self, using: dek) else {
                return nil
            }
            let entry = DecryptedIndexEntry(id: record.id, metadata: metadata)
            return (entry, record.lastAccessedAt ?? record.createdAt)
        }
        // §3 — most-recently-accessed first; falls back to createdAt for never-revealed items.
        items = decrypted.sorted { $0.1 > $1.1 }.map(\.0)
        // Widgets/PinnedVariableWidget.swift reads these across the App
        // Group boundary — an id and a category, never the pinned item's
        // name or value.
        let pinned = items.first(where: \.isPinned)
        WidgetBridge.pinnedItemID = pinned?.id
        WidgetBridge.pinnedItemCategory = pinned?.category
        // The widget's own Timeline policy is .never — it only re-renders
        // when told to. Without this, a widget already on the Lock Screen
        // would keep showing whatever it rendered the first time it was
        // added, forever, regardless of what gets pinned/unpinned afterward.
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetBridge.pinnedWidgetKind)
    }

    /// "hotel key code" case from the expiration metadata discussion: items
    /// marked delete-on-expiration quietly disappear the next time the app
    /// is opened after they expire — no server, no background task, just an
    /// opportunistic check on every unlock. Items that only *notify*
    /// (deleteOnExpiration == false) are left untouched here; that's
    /// ExpirationNotifier's job, on a schedule, independent of app launches.
    @discardableResult
    private func sweepExpiredTemporaryItems(_ records: [QuickVar]) -> Bool {
        guard let dek = session.dek else { return false }
        let now = Date()
        var didDelete = false
        for record in records {
            guard let metadata = try? CryptoBox.openCodable(record.encryptedMetadata, as: QuickVarMetadata.self, using: dek) else { continue }
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

    func add(_ fields: QuickVarFields, value: String) throws {
        guard let dek = session.dek else { throw QuickVarStoreError.locked }
        let metadata = QuickVarMetadata(
            name: fields.name,
            aliases: fields.aliases,
            category: fields.category,
            format: fields.format,
            expiresAt: fields.expiresAt,
            deleteOnExpiration: fields.deleteOnExpiration,
            isEmergencyAccessible: fields.isEmergencyAccessible,
            isPinned: fields.isPinned
        )
        let record = QuickVar(
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

    func update(id: UUID, fields: QuickVarFields, value: String?) throws {
        guard let dek = session.dek else { throw QuickVarStoreError.locked }
        guard let record = try fetchRecord(id: id) else { throw QuickVarStoreError.notFound }

        let metadata = QuickVarMetadata(
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

    /// Backup/BackupCodec.swift re-encrypts this under a user password
    /// before it ever touches disk — decrypting every record here is the
    /// one other place (besides revealValue()) plaintext ever exists, and
    /// only ever transiently in memory.
    func exportBackupItems() throws -> [BackupItem] {
        guard let dek = session.dek else { throw QuickVarStoreError.locked }
        guard let records = try? modelContext.fetch(FetchDescriptor<QuickVar>()) else { return [] }
        return records.compactMap { record in
            guard let metadata = try? CryptoBox.openCodable(record.encryptedMetadata, as: QuickVarMetadata.self, using: dek),
                  let valueData = try? CryptoBox.open(record.encryptedValue, using: dek),
                  let value = String(data: valueData, encoding: .utf8) else {
                return nil
            }
            return BackupItem(
                name: metadata.name,
                aliases: metadata.aliases,
                category: metadata.category,
                format: metadata.format,
                expiresAt: metadata.expiresAt,
                deleteOnExpiration: metadata.deleteOnExpiration,
                isEmergencyAccessible: metadata.isEmergencyAccessible,
                isPinned: metadata.isPinned,
                value: value
            )
        }
    }

    /// Adds every item as new — deliberately no de-duplication or
    /// overwrite-by-name. Restoring should never silently clobber
    /// something already on this device; routes through the exact same
    /// add() as the UI, so emergency payload sealing, expiration
    /// reminders, and single-pin enforcement all happen for free.
    func importBackupItems(_ items: [BackupItem]) throws {
        for item in items {
            let fields = QuickVarFields(
                name: item.name,
                aliases: item.aliases,
                category: item.category,
                format: item.format,
                expiresAt: item.expiresAt,
                deleteOnExpiration: item.deleteOnExpiration,
                isEmergencyAccessible: item.isEmergencyAccessible,
                isPinned: item.isPinned
            )
            try add(fields, value: item.value)
        }
    }

    /// SPEC.md §15.1 — decrypts only the single requested record, never bulk.
    func revealValue(id: UUID) throws -> String {
        guard let dek = session.dek else { throw QuickVarStoreError.locked }
        guard let record = try fetchRecord(id: id) else { throw QuickVarStoreError.notFound }
        record.lastAccessedAt = Date()
        try modelContext.save()
        let opened = try CryptoBox.open(record.encryptedValue, using: dek)
        guard let string = String(data: opened, encoding: .utf8) else { throw QuickVarStoreError.corrupt }
        reload()
        return string
    }

    /// Deliberately independent of the normal session gate (§2) — this is
    /// the entire point of Emergency Info. Uses the separate, weaker-gated
    /// EmergencyKeyStore, never `session.dek`, so it works even when locked.
    func fetchEmergencyItems() -> [EmergencyPayload] {
        guard let records = try? modelContext.fetch(FetchDescriptor<QuickVar>()) else { return [] }
        guard let key = try? emergencyKeyStore.fetchOrCreateKey() else { return [] }
        return records.compactMap { record in
            guard let payload = record.emergencyPayload else { return nil }
            return try? CryptoBox.openCodable(payload, as: EmergencyPayload.self, using: key)
        }
    }

    private func sealEmergencyPayloadIfNeeded(fields: QuickVarFields, value: String) throws -> Data? {
        guard fields.isEmergencyAccessible else { return nil }
        let key = try emergencyKeyStore.fetchOrCreateKey()
        let payload = EmergencyPayload(name: fields.name, value: value)
        return try CryptoBox.sealCodable(payload, using: key)
    }

    /// Only one QuickVar can be pinned to the Lock Screen widget at a time —
    /// enforced here rather than in the UI, so it holds regardless of entry
    /// point (Add, Edit, or a future one).
    private func unpinOtherRecords(except exceptId: UUID, dek: SymmetricKey) throws {
        guard let records = try? modelContext.fetch(FetchDescriptor<QuickVar>()) else { return }
        for record in records where record.id != exceptId {
            guard var metadata = try? CryptoBox.openCodable(record.encryptedMetadata, as: QuickVarMetadata.self, using: dek) else { continue }
            guard metadata.isPinned else { continue }
            metadata.isPinned = false
            record.encryptedMetadata = try CryptoBox.sealCodable(metadata, using: dek)
        }
        try modelContext.save()
    }

    private func scheduleOrCancelReminder(id: UUID, fields: QuickVarFields) {
        if let expiresAt = fields.expiresAt, !fields.deleteOnExpiration {
            ExpirationNotifier.scheduleReminder(for: id, expiresAt: expiresAt)
        } else {
            ExpirationNotifier.cancelReminder(for: id)
        }
    }

    private func fetchRecord(id: UUID) throws -> QuickVar? {
        let descriptor = FetchDescriptor<QuickVar>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }
}
