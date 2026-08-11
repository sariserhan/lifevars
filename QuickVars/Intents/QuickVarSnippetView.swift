import SwiftUI

/// Rendered inline by Siri in response to CheckQuickVarIntent — never a
/// notification (no Lock Screen banner, no Notification Center persistence,
/// no cross-device mirroring), just a one-time result for the person who
/// just spoke the request. Copy is deliberately plain, no "tap to copy" —
/// this view exists for exactly as long as Siri's own UI keeps it on
/// screen, which QuickVars doesn't control the lifecycle of.
struct QuickVarSnippetView: View {
    enum State {
        case revealed(name: String, value: String)
        case notFound
        case ambiguous
        case authFailed
    }

    let state: State

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch state {
            case .revealed(let name, let value):
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.semibold)
                    .textSelection(.disabled)
            case .notFound:
                Label("No match for that", systemImage: "questionmark.circle")
                    .font(.subheadline)
            case .ambiguous:
                Label("More than one match — try a more specific name", systemImage: "list.bullet")
                    .font(.subheadline)
            case .authFailed:
                Label("Couldn't verify it's you", systemImage: "faceid")
                    .font(.subheadline)
            }
        }
        .padding()
    }
}
