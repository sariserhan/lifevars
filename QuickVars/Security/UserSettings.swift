import Foundation
import SwiftUI

enum UnlockMethod: String {
    case faceIDOnly
    case faceIDOrPasscode
}

enum AppearanceOption: String, CaseIterable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum UserSettings {
    enum Keys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let hasSeenFirstQuickVarPrompt = "hasSeenFirstQuickVarPrompt"
        static let biometricEnabled = "biometricEnabled"
        static let unlockMethod = "unlockMethod"
        static let lockOnBackground = "lockOnBackground"
        static let autoHideSeconds = "autoHideSeconds"
        static let appearance = "appearance"
    }

    static var biometricEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.biometricEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.biometricEnabled) }
    }

    /// SPEC.md §2.4 — Face ID Only isn't a valid choice without enrolled biometry,
    /// so the stored preference only applies once biometricEnabled is true.
    static var unlockMethod: UnlockMethod {
        get {
            guard biometricEnabled else { return .faceIDOrPasscode }
            let raw = UserDefaults.standard.string(forKey: Keys.unlockMethod)
            return UnlockMethod(rawValue: raw ?? "") ?? .faceIDOnly
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.unlockMethod) }
    }

    static var lockOnBackground: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.lockOnBackground) == nil { return true }
            return UserDefaults.standard.bool(forKey: Keys.lockOnBackground)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lockOnBackground) }
    }

    static var autoHideSeconds: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: Keys.autoHideSeconds)
            return value == 0 ? 30 : value
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.autoHideSeconds) }
    }
}
