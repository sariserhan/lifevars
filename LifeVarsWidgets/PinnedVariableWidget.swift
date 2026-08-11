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
    @Environment(\.widgetFamily) private var family
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

    /// A big, bold "{ = }" — the same brand mark used on LockScreenView and
    /// the Watch app's ask screen — as the dominant element, the way most
    /// apps lead with their actual logo on a Lock Screen widget rather than
    /// small captioned text. The category emoji is still there, just as a
    /// small secondary detail underneath/beside it, not competing for
    /// attention with the mark itself.
    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 1) {
                Text("{=}")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                if let emoji = entry.category?.emoji {
                    Text(emoji)
                        .font(.system(size: 11))
                }
            }
            .widgetAccentable()
        default:
            HStack(spacing: 8) {
                Text("{ = }")
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                VStack(alignment: .leading, spacing: 1) {
                    Text("LifeVars")
                        .font(.system(size: 12, weight: .semibold))
                    if let emoji = entry.category?.emoji {
                        Text(emoji)
                            .font(.system(size: 11))
                    }
                }
            }
            .widgetAccentable()
        }
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
