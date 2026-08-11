import Foundation
import LocalAuthentication
import CryptoKit
import SwiftUI

/// SPEC.md §2.2 — the one gate, reused everywhere. `requireUnlockedSession()`
/// returns instantly if a session is already open; it only re-prompts after a
/// background-triggered lock (§2.3).
@MainActor
final class SessionManager: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published var lastError: String?

    private(set) var dek: SymmetricKey?
    private var context: LAContext?
    private let keyStore = KeychainDEKStore()

    func unlock() async {
        // SPEC.md §15.2 — a device with no passcode set can't satisfy any
        // access-control policy we use, and would otherwise just loop the
        // user on a retry button that can never succeed. Check for that
        // specific, explainable case before attempting the real fetch.
        let probeContext = LAContext()
        var probeError: NSError?
        if !probeContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &probeError) {
            if let laError = probeError, laError.code == LAError.passcodeNotSet.rawValue {
                lastError = "Set a device passcode in Settings to use LifeVars."
            } else {
                lastError = "Your encrypted data could not be accessed. This can happen if your device's security settings changed."
            }
            isUnlocked = false
            return
        }

        let newContext = LAContext()
        newContext.localizedReason = "Unlock LifeVars"
        do {
            let key = try keyStore.fetchOrCreateDEK(context: newContext)
            context = newContext
            dek = key
            isUnlocked = true
            lastError = nil
        } catch {
            lastError = KeychainDEKStore.describeFailure(error)
            isUnlocked = false
        }
    }

    func requireUnlockedSession() async -> Bool {
        if isUnlocked { return true }
        await unlock()
        return isUnlocked
    }

    func lock() {
        context?.invalidate()
        context = nil
        dek = nil
        isUnlocked = false
        lastError = nil
    }

    /// SPEC.md §2.3 — backgrounding is the real security boundary, not the
    /// Reveal-screen countdown.
    func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .background, UserSettings.lockOnBackground else { return }
        lock()
    }
}
