import SwiftUI

/// SPEC.md §10 — shown when voice resolves to more than one top-confidence
/// candidate. Auth happens after the user picks, not before this list shows.
struct DisambiguationQuery: Identifiable {
    let id = UUID()
    let heading: String
    let candidates: [DecryptedIndexEntry]
}

struct DisambiguationView: View {
    let query: DisambiguationQuery
    let onSelect: (DecryptedIndexEntry) -> Void

    var body: some View {
        NavigationStack {
            List(query.candidates) { item in
                Button {
                    onSelect(item)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: (item.category ?? .other).symbolName)
                            .foregroundStyle(.secondary)
                        Text(item.name)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle(query.heading)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
