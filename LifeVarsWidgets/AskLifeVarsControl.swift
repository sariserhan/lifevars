import AppIntents
import SwiftUI
import WidgetKit

/// Control Center control (iOS 18+ ControlKit). Same shape as
/// FindLifeVarIntent (Intents/FindLifeVarIntent.swift): `openAppWhenRun`
/// foregrounds the app after perform() runs in the extension process, so all
/// perform() can safely do is flip a flag — there's no DEK in this process to
/// touch even by mistake. HomeView.checkPendingVoiceActivation() picks it up
/// on the next foreground and starts listening through the exact same
/// VoiceRecognizer + Matcher path as tapping the mic by hand.
@available(iOS 18.0, *)
struct AskLifeVarsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.serhansari.LifeVars.widgets.ask") {
            ControlWidgetButton(action: ActivateVoiceIntent()) {
                Label("Ask LifeVars", systemImage: "mic.fill")
            }
        }
        .displayName("Ask LifeVars")
        .description("Open LifeVars and start listening.")
    }
}

@available(iOS 18.0, *)
struct ActivateVoiceIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask LifeVars"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        WidgetBridge.setPendingActivateVoice()
        return .result()
    }
}
