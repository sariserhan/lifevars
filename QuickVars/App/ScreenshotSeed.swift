import Foundation

// ponytail: throwaway App Store screenshot tooling, not a feature. Only does
// anything when launched with `-ASOScreenshotSeed` (never present in a real
// build) and only compiled into DEBUG. Safe to delete once screenshots are
// captured.
#if DEBUG
enum ScreenshotSeed {
    // Single `-ASOScreenshotScreen <name>` launch argument drives both
    // "is this a screenshot launch" and "which screen" — NSArgumentDomain
    // pairs each "-key" with the *next* argv token as its value regardless
    // of that token's own contents, so two separate flags (e.g.
    // `-ASOScreenshotSeed -ASOScreenshotScreen home`) silently mis-pair.
    // One key-value pair sidesteps that entirely.
    static var isActive: Bool {
        UserDefaults.standard.string(forKey: "ASOScreenshotScreen") != nil
    }

    static var screen: String {
        UserDefaults.standard.string(forKey: "ASOScreenshotScreen") ?? "home"
    }

    struct Item {
        let name: String
        let value: String
        var expiresInDays: Int? = nil
        var deleteOnExpiration = false
        var isEmergencyAccessible = false
    }

    /// Realistic, non-sensitive sample data spanning several categories —
    /// Classification.swift assigns category/aliases from the name, same as
    /// a real user typing these in. Order matters: HomeView sorts most-
    /// recently-created first (QuickVarStore.reload), so the "hero" items
    /// for the Home screenshot are listed last, landing at the top.
    static let items: [Item] = [
        // §19.2 emergency info — safe categories only (screenshot 06).
        Item(name: "Blood Type", value: "O Positive", isEmergencyAccessible: true),
        Item(name: "Penicillin Allergy", value: "Severe — carries EpiPen", isEmergencyAccessible: true),
        Item(name: "Emergency Contact", value: "Dana Sari — (415) 555-0148", isEmergencyAccessible: true),
        // §19.1 expiration — generic name on purpose (screenshot 05).
        // deleteOnExpiration: true so this takes the cancel-reminder path
        // (QuickVarStore.scheduleOrCancelReminder) instead of scheduling one,
        // which would otherwise pop the notification-permission system alert
        // and block unattended screenshot capture. The row's expiration
        // badge shows either way — it only depends on `expiresAt`.
        Item(name: "Travel Document Number", value: "TD-2291847", expiresInDays: 45, deleteOnExpiration: true),
        Item(name: "Costco Membership Number", value: "111843205512"),
        Item(name: "Auto Insurance Policy", value: "PLC-8823-9401"),
        Item(name: "Storage Locker Combination", value: "12-34-27"),
        Item(name: "Garage Gate Code", value: "4471#"),
        Item(name: "Home WiFi Password", value: "Sunflower$47"),
        Item(name: "Audi VIN", value: "WAUZZZ8V9KA091234")
    ]

    /// Routed through the same encrypted `QuickVarStore.add()` every real
    /// entry uses — no bypass of the encryption path, just pre-filled data.
    @MainActor
    static func seedIfNeeded(store: QuickVarStore) {
        for item in items where !store.nameExists(item.name) {
            let expiresAt = item.expiresInDays.map { Date().addingTimeInterval(TimeInterval($0 * 86400)) }
            let classification = Classification.classify(name: item.name)
            let fields = QuickVarFields(
                name: item.name,
                aliases: classification.aliases,
                category: classification.category,
                format: classification.format,
                expiresAt: expiresAt,
                deleteOnExpiration: item.deleteOnExpiration,
                isEmergencyAccessible: item.isEmergencyAccessible,
                isPinned: false
            )
            try? store.add(fields, value: item.value)
        }
    }
}
#endif
