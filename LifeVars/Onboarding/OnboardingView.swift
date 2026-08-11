import SwiftUI

/// SPEC.md §1 — five screens: what LifeVars is, what you'd store, how
/// retrieval actually works (voice included), where it lives (local +
/// encrypted), then the Face ID enable action. The "first LifeVar" prompt
/// (§1.4) is deferred until the Add flow exists (dev step 5); for now,
/// finishing onboarding goes straight to the session gate / Home.
struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject private var session: SessionManager
    @State private var page = 0
    @State private var faceIDMessage: String?

    private let lastPage = 4

    var body: some View {
        VStack {
            TabView(selection: $page) {
                WelcomePage().tag(0)
                WhatItsForPage().tag(1)
                HowItWorksPage().tag(2)
                SecurityPage().tag(3)
                FaceIDPage(onEnable: enableFaceID, onSkip: finish, message: faceIDMessage).tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            if page < lastPage {
                Button("Next") { withAnimation { page += 1 } }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 32)
            }
        }
    }

    private func enableFaceID() {
        Task {
            await session.unlock()
            if session.isUnlocked {
                UserSettings.biometricEnabled = true
                finish()
            } else {
                UserSettings.biometricEnabled = false
                faceIDMessage = "You can enable this later in Settings."
            }
        }
    }

    private func finish() {
        hasCompletedOnboarding = true
    }
}

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("{ = }")
                .font(.system(size: 56, weight: .light, design: .monospaced))
            Text("LifeVars")
                .font(.largeTitle.bold())
            Text("The things you shouldn't have to remember.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
    }
}

private struct WhatItsForPage: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("VIN · EIN · Passport\nInsurance · Accounts\nAnything else")
                .multilineTextAlignment(.center)
                .font(.title3)
            Text("Save once. Ask whenever you need it.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct HowItWorksPage: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Ask, and it's there.")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                Text("Type a name, or just say it out loud —")
                Text("\u{201C}What's my Audi VIN?\u{201D}")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                Text("and the answer appears right on your screen. No digging through Photos or Notes.")
            }
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
        }
    }
}

private struct SecurityPage: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Stays on your phone.\nNowhere else.")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text("Every LifeVar is encrypted the moment you save it. No account, no server, no cloud — this device is the only place any of it ever exists.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Text("That cuts both ways: losing this device means losing your LifeVars — unless you've made your own encrypted, password-protected backup (Settings → Backup).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 8)
        }
    }
}

private struct FaceIDPage: View {
    let onEnable: () -> Void
    let onSkip: () -> Void
    let message: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Only you can open\nLifeVars")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text("Face ID unlocks everything at once — no separate password to remember, no prompt per item.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Enable Face ID", action: onEnable)
                .buttonStyle(.borderedProminent)
                .padding(.top, 12)

            Button("Set up later", action: onSkip)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }
}
