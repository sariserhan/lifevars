import Foundation

/// Shared between the main app and the LifeVarsWidgets extension via the App
/// Group entitlement — the only channel available across that process
/// boundary. Carries no plaintext value or name, ever: just an opaque item
/// id (already considered safe to store in the clear, same as `LifeVar.id`
/// on disk — SPEC.md §14) and a one-shot action flag.
enum AppGroup {
    static let id = "group.com.serhansari.LifeVars"
}

enum WidgetBridge {
    /// Matches PinnedVariableWidget's `kind` — shared so LifeVarStore can
    /// tell WidgetKit to reload the right widget after pinnedItemID changes.
    static let pinnedWidgetKind = "com.serhansari.LifeVars.widgets.pinned"

    private enum Key {
        static let pinnedItemID = "widget.pinnedItemID"
        static let pinnedItemCategory = "widget.pinnedItemCategory"
        static let pendingActivateVoice = "widget.pendingActivateVoice"
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: AppGroup.id) }

    /// Written by LifeVarStore.reload() whenever the pinned item changes;
    /// read by the Lock Screen widget's timeline provider to know whether a
    /// pin exists. Never the item's name or value.
    static var pinnedItemID: UUID? {
        get {
            guard let raw = defaults?.string(forKey: Key.pinnedItemID) else { return nil }
            return UUID(uuidString: raw)
        }
        set { defaults?.set(newValue?.uuidString, forKey: Key.pinnedItemID) }
    }

    /// Category only, by direct request after weighing it against showing
    /// the pinned item's actual name — a category hint is a deliberate,
    /// bounded middle ground: enough to glance-recognize which pin it is,
    /// never enough to expose what it actually is.
    static var pinnedItemCategory: Category? {
        get {
            guard let raw = defaults?.string(forKey: Key.pinnedItemCategory) else { return nil }
            return Category(rawValue: raw)
        }
        set { defaults?.set(newValue?.rawValue, forKey: Key.pinnedItemCategory) }
    }

    /// Set by the Control Center "Ask LifeVars" control's AppIntent, which
    /// runs in the extension process; consumed once by the main app on next
    /// foreground — the cross-process analog of PendingSiriQuery, which can
    /// stay in-memory only because Siri intents run in-process here.
    static func setPendingActivateVoice() {
        defaults?.set(true, forKey: Key.pendingActivateVoice)
    }

    static func consumePendingActivateVoice() -> Bool {
        guard defaults?.bool(forKey: Key.pendingActivateVoice) == true else { return false }
        defaults?.set(false, forKey: Key.pendingActivateVoice)
        return true
    }
}
