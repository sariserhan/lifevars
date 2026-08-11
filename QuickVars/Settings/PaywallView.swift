import SwiftUI

/// SPEC.md §11.1 — voice, search, and Face ID are free; Pro only removes the
/// item cap and unlocks roadmap features. Never paywall the core "ask and
/// get an answer" loop.
struct PaywallView: View {
    @EnvironmentObject private var storeManager: StoreManager
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("QuickVars Pro")
                    .font(.largeTitle.bold())

                VStack(alignment: .leading, spacing: 10) {
                    Label("Unlimited QuickVars", systemImage: "infinity")
                    Label("Siri integration", systemImage: "mic")
                    Label("Encrypted backup", systemImage: "icloud")
                }
                .foregroundStyle(.secondary)

                Spacer()

                if let product = storeManager.product {
                    Button {
                        purchase()
                    } label: {
                        Text(isPurchasing ? "Purchasing..." : "Unlock — \(product.displayPrice)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPurchasing)

                    Text("one-time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let error = storeManager.purchaseError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                } else {
                    ProgressView()
                }

                Button("Restore Purchase") {
                    Task { await storeManager.restore() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: storeManager.isPro) { _, isPro in
                if isPro { dismiss() }
            }
        }
    }

    private func purchase() {
        isPurchasing = true
        Task {
            await storeManager.purchase()
            isPurchasing = false
        }
    }
}
