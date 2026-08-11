import SwiftUI

/// Split out from HomeView so the alias/expiration popovers have real,
/// per-row `@State` to attach to — a plain helper function can't hold
/// `@State`, and a single HomeView-level `@State` shared by every row
/// couldn't tell rows apart (and popovers attached far from their actual
/// trigger button lose their anchor, defaulting to some generic on-screen
/// position instead of appearing next to the button that opened them).
struct LifeVarRow: View {
    let item: DecryptedIndexEntry
    let onReveal: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isShowingAliases = false
    @State private var isShowingExpiration = false
    @State private var isShowingEmergencyInfo = false
    @State private var isShowingPinInfo = false

    var body: some View {
        HStack(spacing: 12) {
            // The reveal-tap target and the badge tray are siblings, not
            // nested — a Button inside another Button's label doesn't
            // reliably register its own taps in SwiftUI.
            Button(action: onReveal) {
                HStack(spacing: 12) {
                    Image(systemName: (item.category ?? .other).symbolName)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .foregroundStyle(.primary)
                        // §14 — VoiceOver would otherwise read every dot as
                        // the literal word "bullet"; hide the decoration
                        // and give the row one sensible combined label.
                        Text(String(repeating: "•", count: 12))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.name), hidden value")

            Spacer()

            badges
        }
        .swipeActions {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Edit", action: onEdit)
                .tint(.blue)
        }
    }

    /// Every badge is tappable — each opens a popover anchored to that
    /// exact button explaining what it means, same pattern for all four.
    private var badges: some View {
        HStack(spacing: 10) {
            if !item.aliases.isEmpty {
                Button {
                    isShowingAliases = true
                } label: {
                    Image(systemName: "character.bubble.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Aliases")
                .popover(isPresented: $isShowingAliases) {
                    aliasesPopover
                }
            }
            if item.expiresAt != nil {
                Button {
                    isShowingExpiration = true
                } label: {
                    Image(systemName: "clock.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.deleteOnExpiration ? "Deletes automatically" : "Has an expiration reminder")
                .popover(isPresented: $isShowingExpiration) {
                    expirationPopover
                }
            }
            if item.isEmergencyAccessible {
                Button {
                    isShowingEmergencyInfo = true
                } label: {
                    Image(systemName: "staroflife.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Emergency accessible")
                .popover(isPresented: $isShowingEmergencyInfo) {
                    infoPopover(
                        title: "Emergency Access",
                        message: "Visible from the Lock Screen without Face ID — for things like blood type or an emergency contact. Turn this off in Edit if you don't want that anymore."
                    )
                }
            }
            if item.isPinned {
                Button {
                    isShowingPinInfo = true
                } label: {
                    Image(systemName: "pin.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pinned to Lock Screen")
                .popover(isPresented: $isShowingPinInfo) {
                    infoPopover(
                        title: "Pinned to Lock Screen",
                        message: "Shown as a shortcut widget — it only ever displays a generic locked icon, never this item's name or value. Face ID is still required to open it."
                    )
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var aliasesPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Also known as")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(item.aliases, id: \.self) { alias in
                Text(alias)
            }
        }
        .padding()
        .presentationCompactAdaptation(.popover)
    }

    private var expirationPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.deleteOnExpiration ? "Deletes" : "Expires")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let expiresAt = item.expiresAt {
                Text(expiresAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.headline)
            }
        }
        .padding()
        .presentationCompactAdaptation(.popover)
    }

    /// Shared shape for the two plain-explanation badges (Emergency Access,
    /// Pin) — aliases/expiration show actual per-item data instead, so they
    /// keep their own dedicated layouts above.
    private func infoPopover(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: 260, alignment: .leading)
        .presentationCompactAdaptation(.popover)
    }
}
