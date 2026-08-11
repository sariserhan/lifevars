import SwiftUI

/// SPEC.md §0 — RootView switches between Onboarding, LockScreen, and Home.
/// There is no path from onboarding straight to Home: even a "Set up later"
/// user passes through the session gate once onboarding completes (§2, the
/// security invariants — no unauthenticated surface in QuickVars).
struct RootView: View {
    @EnvironmentObject private var session: SessionManager
    @AppStorage(UserSettings.Keys.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
            } else if !session.isUnlocked {
                LockScreenView()
            } else {
                HomeView()
            }
        }
        .animation(.default, value: hasCompletedOnboarding)
        .animation(.default, value: session.isUnlocked)
    }
}
