# QuickVars

> The things you shouldn't have to remember.

Save a value once (`audi_vin = WAU...`), ask for it later by typing or voice, authenticate, get the answer. No accounts, no cloud, no server — everything is encrypted and stored on-device.

Full product plan: see the product plan doc referenced in `SPEC.md`. Screen-by-screen build spec, security architecture, and dev order: **`SPEC.md`** — read that before touching `Security/` or `Models/`, it explains the *why* behind decisions that aren't obvious from the code (e.g. why there's exactly one Keychain-gated auth mechanism and not a second manual one).

## Stack

Native SwiftUI, iOS 17+. No backend, no third-party dependencies.

- **LocalAuthentication + Keychain** — session unlock (Face ID or Face ID + passcode), one data-encryption key sealed behind a `SecAccessControl`-protected Keychain item
- **CryptoKit** — AES-GCM for every encrypted value/metadata blob
- **Speech** — on-device voice transcription only, no server fallback
- **App Intents** — Siri integration (V1 stretch, see `SPEC.md` §13)

## Project setup

The Xcode project is generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `QuickVars.xcodeproj` is not hand-edited and not something you should open Xcode's project editor to change. Edit `project.yml` (or add/remove files under `QuickVars/`), then regenerate:

```sh
brew install xcodegen   # if you don't have it
xcodegen generate
```

Do this after adding or removing any Swift file — XcodeGen globs `QuickVars/` for sources, so new files need a regenerate to show up in the project (Xcode will auto-detect the change if it's already open).

### Build & run

```sh
xcodebuild -project QuickVars.xcodeproj -scheme QuickVars \
  -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
```

Or just open `QuickVars.xcodeproj` in Xcode and hit Run.

**Simulator caveats**:
- Keychain biometric access control (`.biometryCurrentSet` / `.userPresence`) evaluates almost instantly with no visible system sheet unless you explicitly enable Simulator → Features → Face ID → Enrolled.
- Voice transcription has no real microphone input in this environment (no host-audio passthrough) — the permission flow and `AVAudioEngine` setup/teardown work and are verified, but actual speech→text needs a real device.
- Siri does not function in the Simulator at all, on any app — the `FindQuickVarIntent` build/registration is verified, but invoking it via Siri needs a real device.
- StoreKit purchases need an Xcode Run-button (or `xcodebuild test`) launch — `QuickVars.storekit` is wired into the scheme, but `simctl launch` bypasses Xcode's scheme-driven launch entirely, so the local config never attaches.

See `TODO.md` for exactly what's verified live vs. code-reviewed-only for each of these.

## Layout

```
QuickVars/
├── App/          QuickVarsApp (entry point, scenePhase → lock + appearance wiring), RootView, AppSwitcherOverlay (SPEC.md §2.3)
├── Onboarding/    3-screen onboarding (SPEC.md §1)
├── Lock/          LockScreenView — the session gate's UI (SPEC.md §2.1)
├── Home/          HomeView — list, search, mic (SPEC.md §3, §4)
├── Reveal/        RevealView — countdown, re-mask, Copy, screen-recording guard (SPEC.md §5)
├── Variables/     AddVariableView, EditVariableView (SPEC.md §6, §7)
├── Voice/         VoiceRecognizer, DisambiguationView, PendingSiriQuery (SPEC.md §4, §10, §13)
├── Intents/       FindQuickVarIntent + AppShortcuts — never returns a value to Siri (SPEC.md §13)
├── Settings/      SettingsView, PaywallView, Privacy/Security info screens (SPEC.md §11)
├── Store/         StoreManager — StoreKit 2 non-consumable
├── Data/          Persistence (SwiftData, excluded from backup per §15.2), QuickVarStore (encrypt/decrypt CRUD)
├── Models/        QuickVar, QuickVarMetadata, Category, Classification (§9.1), Matcher (§9.2)
└── Security/      UserSettings, KeychainDEKStore, SessionManager, CryptoBox — the part SPEC.md §15
                    says not to improvise. One Keychain-gated DEK, no second auth path.
```

## Status

The full core loop from the acceptance test (SPEC.md §17) is built: onboarding → session gate → add/edit/delete → search → voice → reveal → Settings/Paywall → Siri handoff. Everything through dev step 15 is done — see `TODO.md` for the verified-live vs. code-reviewed-only breakdown on each step, and what's left (step 16, TestFlight, which needs your Apple Developer credentials directly).
