import SwiftUI

/// Deliberately reachable without Face ID, mirroring the trade-off Apple's
/// own Medical ID makes: a narrow, user-curated set of fields the user
/// explicitly opted in (Edit's "Emergency Access" toggle), sealed under a
/// separate, weaker-gated key (EmergencyKeyStore) that this view is the only
/// thing that ever touches. No countdown, no re-mask, no screenshot guard —
/// the entire point is instant access when normal authentication isn't an
/// option (unconscious, phone handed to someone else in an emergency).
struct EmergencyAccessView: View {
    @EnvironmentObject private var store: LifeVarStore
    @Environment(\.dismiss) private var dismiss

    @State private var items: [EmergencyPayload] = []

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    List(items, id: \.name) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(.headline)
                            Text(item.value)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Emergency Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .top) {
                Text("Visible without Face ID")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.15))
            }
        }
        .onAppear {
            items = store.fetchEmergencyItems()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cross.case")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No emergency info set up.")
                .foregroundStyle(.secondary)
        }
    }
}
