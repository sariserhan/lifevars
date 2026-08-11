import SwiftUI

/// SPEC.md §15 — plain-language explanation of the encryption model, kept
/// in sync with what the code actually does rather than aspirational copy.
struct SecurityInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Every value, name, and alias you save is encrypted before it touches storage.")
                    .font(.title3.bold())
                Text("The encryption key is generated on this device and sealed in the iOS Keychain behind Face ID or your device passcode — QuickVars itself never sees it outside an unlocked session.")
                Text("Opening the app authenticates you once; that session covers everything you do until the app backgrounds or you lock it manually.")
                Text("Face ID Only is the strongest unlock method, but it has one real trade-off: if you add, remove, or re-enroll a Face ID face, iOS invalidates that protection and your QuickVars can't be recovered — there's no passcode fallback in that mode. Face ID + Passcode avoids that failure mode.")
                Text("Uninstalling QuickVars deletes everything on this device. There's no backup yet, so that action can't be undone.")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Security")
        .navigationBarTitleDisplayMode(.inline)
    }
}
