import AppIntents
import LocalAuthentication
import SwiftData
import SwiftUI

/// The headless counterpart to FindQuickVarIntent — this one authenticates
/// and decrypts entirely inside its own perform(), without ever bringing the
/// app to the foreground, and shows the result as an inline Siri snippet
/// instead of opening the app. `openAppWhenRun = false` is the whole point.
///
/// This is a deliberate, narrow exception to "the app never returns a
/// decrypted value to Siri" (FindQuickVarIntent's rule, SPEC.md §13): the
/// trade for skipping the app-open step is that the result briefly exists as
/// system Siri UI, whose lifecycle QuickVars doesn't control the way it
/// controls RevealView's auto-hide and no-screen-recording guard. What it
/// deliberately does NOT do is post a notification — a Lock Screen banner
/// would be strictly worse (persists in Notification Center, can mirror to
/// other devices via Handoff) than a one-time Siri response to a request the
/// user just spoke.
///
/// Auth is its own momentary LAContext/Keychain fetch (KeychainDEKStore),
/// not SessionManager's — this runs whether or not the main app happens to
/// be alive, and never touches SessionManager's session state either way.
struct CheckQuickVarIntent: AppIntent {
    static var title: LocalizedStringResource = "Check a QuickVar"
    static var description = IntentDescription("Check something you saved in QuickVars with Face ID, without opening the app.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "What to check", requestValueDialog: "What do you want to check?")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let context = LAContext()
        context.localizedReason = "Check a QuickVar"
        guard let dek = try? KeychainDEKStore().fetchOrCreateDEK(context: context) else {
            return .result(view: QuickVarSnippetView(state: .authFailed))
        }

        let modelContext = ModelContext(Persistence.makeContainer())
        switch QuickVarLookup.lookup(query: query, dek: dek, modelContext: modelContext) {
        case .notFound:
            return .result(view: QuickVarSnippetView(state: .notFound))
        case .ambiguous:
            return .result(view: QuickVarSnippetView(state: .ambiguous))
        case .match(let record, let metadata):
            guard let valueData = try? CryptoBox.open(record.encryptedValue, using: dek),
                  let value = String(data: valueData, encoding: .utf8) else {
                return .result(view: QuickVarSnippetView(state: .notFound))
            }
            record.lastAccessedAt = Date()
            try? modelContext.save()
            let formatted = metadata.format?.apply(to: value) ?? value
            return .result(view: QuickVarSnippetView(state: .revealed(name: metadata.name, value: formatted)))
        }
    }
}
