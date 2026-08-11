import AppIntents
import SwiftUI
import WidgetKit

/// Control Center control (iOS 18+ ControlKit). Same shape as
/// FindQuickVarIntent (Intents/FindQuickVarIntent.swift): `openAppWhenRun`
/// foregrounds the app after perform() runs in the extension process, so all
/// perform() can safely do is flip a flag — there's no DEK in this process to
/// touch even by mistake. HomeView.checkPendingVoiceActivation() picks it up
/// on the next foreground and starts listening through the exact same
/// VoiceRecognizer + Matcher path as tapping the mic by hand.
@available(iOS 18.0, *)
struct AskQuickVarsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.serhansari.QuickVars.widgets.ask") {
            ControlWidgetButton(action: ActivateVoiceIntent()) {
                Label("Ask QuickVars", systemImage: "mic.fill")
            }
        }
        .displayName("Ask QuickVars")
        .description("Open QuickVars and start listening.")
    }
}

@available(iOS 18.0, *)
struct ActivateVoiceIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask QuickVars"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        WidgetBridge.setPendingActivateVoice()
        return .result()
    }
}
