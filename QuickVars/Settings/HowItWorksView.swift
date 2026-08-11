import SwiftUI

/// A plain-language explainer for the features that don't otherwise have a
/// home in Settings — same "kept in sync with what the code actually does"
/// spirit as PrivacyInfoView/SecurityInfoView, just covering more ground.
struct HowItWorksView: View {
    private struct Item {
        let icon: String
        let title: String
        let body: String
    }

    private let items: [Item] = [
        Item(
            icon: "faceid",
            title: "Face ID unlocks a session, not one item",
            body: "Authenticating once covers everything you do until QuickVars is backgrounded or you lock it manually — you're never re-prompted per item."
        ),
        Item(
            icon: "magnifyingglass",
            title: "Search and voice use the same matcher",
            body: "Typing \"vin\" and saying \"what's my Audi VIN\" resolve the exact same way — one confident match reveals immediately, more than one asks which you meant."
        ),
        Item(
            icon: "tag",
            title: "Categories are a default, not a folder",
            body: "QuickVars guesses a category from the name you type. It's only ever a suggestion — change it any time from the dropdown in Add or Edit, and every item still lives in one flat, searchable list regardless of category."
        ),
        Item(
            icon: "textformat.123",
            title: "SSNs and EINs format themselves",
            body: "A 9-digit value saved under a Social Security or EIN name displays with the right dashes on the Reveal screen. The stored value itself is never changed — this is display-only."
        ),
        Item(
            icon: "clock.badge.exclamationmark",
            title: "Expiration: reminders vs. auto-delete",
            body: "Set an optional expiration date on any item. By default you just get a generic reminder as it approaches — it never names the item. Turn on \"delete automatically when expired\" for something truly temporary, like a one-night hotel key code, and QuickVars quietly removes it the next time you open the app after it lapses."
        ),
        Item(
            icon: "cross.case",
            title: "Emergency Access",
            body: "A per-item toggle in Add or Edit. Items you turn it on for become reachable from the Lock Screen's \"Emergency Info\" button with no Face ID at all — sealed under a separate, deliberately weaker-gated key that never touches the rest of your vault. Off by default for everything. Use it narrowly — blood type, an allergy, an emergency contact — not account numbers."
        ),
        Item(
            icon: "pin",
            title: "Pin to Lock Screen",
            body: "Pick one item to pin, then add the QuickVars widget from your Lock Screen editor. It shows only a generic locked icon — never the name or value. Tapping it opens the app and still requires Face ID before revealing anything. Only one item can be pinned at a time; pinning a new one replaces the old pin."
        ),
        Item(
            icon: "applewatch",
            title: "Apple Watch",
            body: "Ask your Watch the same way you'd ask your phone. It relays the question to your already-unlocked iPhone, which does the actual matching and decrypting — the Watch itself never stores a key or a value."
        ),
        Item(
            icon: "mic",
            title: "\u{201C}Ask QuickVars to find something\u{201D}",
            body: "A Siri command that opens the app, runs Face ID automatically, and lands you on the answer. Siri never sees or speaks the value in this flow."
        ),
        Item(
            icon: "bolt.shield",
            title: "\u{201C}Ask QuickVars to check something\u{201D}",
            body: "A second, separate Siri command: it authenticates with its own Face ID prompt without ever opening the app, and shows the result once as an inline Siri response — never a notification."
        )
    ]

    var body: some View {
        List {
            ForEach(items, id: \.title) { item in
                Section {
                    Label {
                        Text(item.title).font(.subheadline.bold())
                    } icon: {
                        Image(systemName: item.icon)
                    }
                    Text(item.body)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("How It Works")
        .navigationBarTitleDisplayMode(.inline)
    }
}
