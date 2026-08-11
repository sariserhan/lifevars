import WidgetKit
import SwiftUI

/// Lock Screen widget for the item the user pinned in Add/Edit. Deliberately
/// carries only an id and a category across the App Group boundary
/// (Shared/AppGroupBridge) — never the pinned item's name or value. The
/// category is a bounded, deliberate exception weighed directly against
/// showing the actual name: enough to glance-recognize which pin it is
/// (e.g. a car emoji for a Vehicle-category item), never enough to expose
/// what it actually is. The widget is a shortcut, not a display: tapping it
/// opens the app via `lifevars://reveal` and still goes through the normal
/// Face ID session gate (§2) before RevealView shows anything.
struct PinnedVariableEntry: TimelineEntry {
    let date: Date
    let pinnedItemID: UUID?
    let category: Category?
}

struct PinnedVariableProvider: TimelineProvider {
    func placeholder(in context: Context) -> PinnedVariableEntry {
        PinnedVariableEntry(date: Date(), pinnedItemID: UUID(), category: .vehicle)
    }

    func getSnapshot(in context: Context, completion: @escaping (PinnedVariableEntry) -> Void) {
        completion(PinnedVariableEntry(date: Date(), pinnedItemID: WidgetBridge.pinnedItemID, category: WidgetBridge.pinnedItemCategory))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PinnedVariableEntry>) -> Void) {
        let entry = PinnedVariableEntry(date: Date(), pinnedItemID: WidgetBridge.pinnedItemID, category: WidgetBridge.pinnedItemCategory)
        // Pin state only ever changes from inside the app (Add/Edit), which
        // calls WidgetCenter.shared.reloadTimelines itself — no need for a
        // scheduled refresh here.
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct PinnedVariableWidgetView: View {
    let entry: PinnedVariableEntry

    var body: some View {
        content
            .widgetURL(entry.pinnedItemID.flatMap { URL(string: "lifevars://reveal?id=\($0.uuidString)") })
            // Required since iOS 17 for every widget family, Lock Screen
            // accessories included — without it the system shows a "Please
            // adopt containerBackground API" placeholder instead of any
            // actual content. Lock Screen accessory families are always
            // rendered tinted/monochrome by the system regardless of what's
            // here, so an empty background is correct, not a placeholder.
            .containerBackground(for: .widget) {
                Color.clear
            }
    }

    /// Top line is the same brand mark as LockScreenView/the Watch app's
    /// ask screen. Bottom line plays on that same "{ = }" variable motif —
    /// "LifeVars" assigned to a category emoji instead of the item's real
    /// name, the deliberate ceiling described above.
    private var content: some View {
        VStack(spacing: 2) {
            Text("{ = }")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
            Text("{ LifeVars = \(entry.category?.emoji ?? "?") }")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .widgetAccentable()
    }
}

struct PinnedVariableWidget: Widget {
    let kind = WidgetBridge.pinnedWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PinnedVariableProvider()) { entry in
            PinnedVariableWidgetView(entry: entry)
        }
        .configurationDisplayName("Pinned LifeVar")
        .description("A Lock Screen shortcut to one LifeVar you've pinned. Never shows its name or value — Face ID is still required to reveal it.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
