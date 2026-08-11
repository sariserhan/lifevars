import SwiftUI

/// SPEC.md §11 — "the app's actual marketing claim, worth getting right,
/// not boilerplate legal text."
struct PrivacyInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your QuickVars never leave your device.")
                    .font(.title3.bold())
                Text("QuickVars has no account, no server, and no cloud sync in this version. Everything you save is encrypted and stored only on this iPhone.")
                Text("Voice requests are transcribed on-device. What you say is never sent anywhere to be processed — not even to Apple.")
                Text("Nothing you save is ever included in analytics, crash reports, or notifications.")
                Text("Because there's no backend, there's also no backup yet. If you lose this device, your QuickVars are lost with it — see Security for what that means for the unlock method you've chosen.")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
