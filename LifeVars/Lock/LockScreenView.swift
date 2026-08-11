import SwiftUI

/// SPEC.md §2.1 — unlocking is a deliberate tap, not something that fires
/// just from this screen appearing. Face ID/passcode only ever runs in
/// response to you tapping Unlock (or Try Again/Use Passcode after a
/// failure) — every time this screen shows, cold launch, returning from
/// background, or after the manual lock button, the same way.
struct LockScreenView: View {
    @EnvironmentObject private var session: SessionManager
    @State private var isAttempting = false
    @State private var isShowingEmergencyAccess = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("{ = }")
                .font(.system(size: 48, weight: .light, design: .monospaced))
            Text("LifeVars")
                .font(.title2.bold())

            Spacer()

            if let error = session.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button(UserSettings.unlockMethod == .faceIDOnly ? "Try Again" : "Use Passcode") {
                    attemptUnlock()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAttempting)
            } else {
                Button(action: attemptUnlock) {
                    VStack(spacing: 10) {
                        Image(systemName: isAttempting ? "lock.open.fill" : "lock.fill")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(Circle().fill(Color.accentColor))
                        Text(isAttempting ? "Authenticating\u{2026}" : "Unlock")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isAttempting)
                .opacity(isAttempting ? 0.6 : 1)
            }

            Spacer()

            // Deliberately outside the session gate — see EmergencyAccessView.
            Button("Emergency Info") {
                isShowingEmergencyAccess = true
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $isShowingEmergencyAccess) {
            EmergencyAccessView()
        }
    }

    private func attemptUnlock() {
        guard !isAttempting else { return }
        isAttempting = true
        Task {
            await session.unlock()
            isAttempting = false
        }
    }
}
