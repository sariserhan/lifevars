import WidgetKit
import SwiftUI

/// Lock Screen widget for the item the user pinned in Add/Edit. Deliberately
/// carries only an id across the App Group boundary (Shared/AppGroupBridge)
/// — never the pinned item's name, category, or value. The widget is a
/// shortcut, not a display: tapping it opens the app via `lifevars://reveal`
/// and still goes through the normal Face ID session gate (§2) before
/// RevealView shows anything.
struct PinnedVariableEntry: TimelineEntry {
    let date: Date
    let pinnedItemID: UUID?
}

struct PinnedVariableProvider: TimelineProvider {
    func placeholder(in context: Context) -> PinnedVariableEntry {
        PinnedVariableEntry(date: Date(), pinnedItemID: UUID())
    }

    func getSnapshot(in context: Context, completion: @escaping (PinnedVariableEntry) -> Void) {
        completion(PinnedVariableEntry(date: Date(), pinnedItemID: WidgetBridge.pinnedItemID))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PinnedVariableEntry>) -> Void) {
        let entry = PinnedVariableEntry(date: Date(), pinnedItemID: WidgetBridge.pinnedItemID)
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

    private var content: some View {
        VStack(spacing: 2) {
            Image(systemName: entry.pinnedItemID != nil ? "lock.fill" : "pin.slash")
                .font(.system(size: 18))
            Text(entry.pinnedItemID != nil ? "Pinned" : "Not Set")
                .font(.system(size: 10))
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
