import SwiftUI

/// SPEC.md §1 — three screens. The "first LifeVar" prompt (§1.4) is deferred
/// until the Add flow exists (dev step 5); for now, finishing onboarding goes
/// straight to the session gate / Home.
struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject private var session: SessionManager
    @State private var page = 0
    @State private var faceIDMessage: String?

    var body: some View {
        VStack {
            TabView(selection: $page) {
                WelcomePage().tag(0)
                WhatItsForPage().tag(1)
                FaceIDPage(onEnable: enableFaceID, onSkip: finish, message: faceIDMessage).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            if page < 2 {
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

private struct FaceIDPage: View {
    let onEnable: () -> Void
    let onSkip: () -> Void
    let message: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Only you can open\nLifeVars")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text("Protected with Face ID and encrypted on this device.")
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

            Spacer().frame(height: 20)

            Text("Stored only on this device — losing your phone means losing your LifeVars until backup ships.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}
