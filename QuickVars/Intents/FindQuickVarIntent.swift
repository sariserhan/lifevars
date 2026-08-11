import AppIntents

/// SPEC.md §13 — hard rule: the intent never returns a decrypted value to
/// Siri, ever. It can't, structurally — `openAppWhenRun` runs `perform()`
/// inside the app process after launch, but before any session is unlocked,
/// so there's no DEK in memory for it to touch even by mistake. All it does
/// is hand the raw query to the running app; the app then goes through the
/// exact same session gate (§2) and matcher (§9.2) as typed search or
/// in-app voice — no shortcut, no bypass.
struct FindQuickVarIntent: AppIntent {
    static var title: LocalizedStringResource = "Find a QuickVar"
    static var description = IntentDescription("Look up something you saved in QuickVars.")
    static var openAppWhenRun: Bool = true

    // Free-text parameters can't be embedded directly in a shortcut phrase
    // (App Shortcuts only allow AppEntity/AppEnum there, since the system
    // needs an enumerable vocabulary for phrase matching) — and giving Siri
    // an enumerable entity of QuickVar names would mean exposing them outside
    // an unlocked session, which the security model doesn't allow. Instead
    // the phrase stays generic and Siri asks this dialog as a follow-up turn
    // to collect the query by voice.
    @Parameter(title: "What to find", requestValueDialog: "What do you want to find?")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingSiriQuery.shared.query = query
        return .result()
    }
}

struct QuickVarsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FindQuickVarIntent(),
            phrases: [
                "Ask \(.applicationName) to find something",
                "Find something in \(.applicationName)"
            ],
            shortTitle: "Find a QuickVar",
            systemImageName: "curlybraces"
        )
        AppShortcut(
            intent: CheckQuickVarIntent(),
            phrases: [
                "Ask \(.applicationName) to check something",
                "Check something in \(.applicationName)"
            ],
            shortTitle: "Check a QuickVar",
            systemImageName: "faceid"
        )
    }
}
