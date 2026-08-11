# LifeVars — V1 Screen & Interaction Specification

Build spec for native SwiftUI, iOS only, no backend. Companion to `PLAN.md` (product plan). Defines every screen, state, and transition needed to ship V1.

Stack: SwiftUI + Speech + LocalAuthentication + App Intents (V1 stretch, see §15) + Keychain + local encrypted persistence (SwiftData/Core Data store, values *and* names/aliases encrypted at rest, key sealed in Keychain / Secure Enclave).

Feel: a built-in iPhone utility, not a database app or password manager. No tab bar, three primary surfaces only.

## Security invariants — these override every other requirement in this document

If any feature below conflicts with one of these, the invariant wins. Not a checklist to revisit later — a constraint on every screen and every line of §2–§15.

1. Plaintext LifeVar values never leave the device.
2. Plaintext values are never logged, never enter analytics or crash reports.
3. Plaintext values are never sent to Siri, and never spoken by the app.
4. Plaintext values (and the search/voice queries used to find them) are never sent to a server — voice transcription is on-device only, with no fallback (§4).
5. Plaintext values never appear in notifications, app-switcher snapshots, or Spotlight indexing.
6. A value is decrypted only for the single record being shown, only inside an active Reveal/Edit screen — never bulk-decrypted into memory.
7. The decrypted name/alias index (§15) is discarded the moment the session locks.
8. No networking dependency is required to unlock or retrieve a LifeVar. No cloud fallback exists in V1.

**Not a password manager.** LifeVars is for facts you look up occasionally — VIN, EIN, passport number, insurance ID, account numbers, filter sizes, paint colors. It is explicitly not the place for bank passwords, Apple ID credentials, crypto seed phrases, or 2FA recovery codes — nothing in the product stops a user from typing one in, but nothing in the marketing or onboarding should suggest that's the intended use. That's a different security bar than this spec is designed for.

---

## 0. Navigation

```
RootView
├── (first launch) OnboardingFlow — 3 screens, modal
└── (normal launch)
    └── LockScreen (session gate, §2)
        └── HomeView
            ├── AddVariableFlow    (sheet, 2-step wizard, §5)
            ├── EditVariableView   (sheet, §7)
            ├── RevealView         (full-screen cover, §4)
            ├── SettingsView       (sheet, §11)
            └── PaywallView        (sheet, presented when free limit hit)
```

Settings is a small button on Home. No tab bar, no nested stacks — everything is a sheet or cover that returns to Home.

---

## 1. Onboarding

Three screens, swipeable, Next to advance.

### 1.1 Welcome

```
┌────────────────────────────┐
│         [app icon]         │
│         LifeVars            │
│  The things you shouldn't  │
│     have to remember.      │
│                    Next →   │
└────────────────────────────┘
```

### 1.2 What it's for

```
┌────────────────────────────┐
│   VIN · EIN · Passport     │
│   Insurance · Accounts     │
│   Anything else            │
│  Save once. Ask whenever   │
│      you need it.          │
│                    Next →   │
└────────────────────────────┘
```

Static example list, not interactive.

### 1.3 Face ID

```
┌────────────────────────────┐
│   Only you can open        │
│        LifeVars              │
│                             │
│  Protected with Face ID     │
│  and encrypted on this      │
│  device.                    │
│                             │
│   [ Enable Face ID ]        │
│      Set up later           │
│                             │
│  Stored only on this        │
│  device — losing your       │
│  phone means losing your    │
│  LifeVars until backup      │
│  ships.                     │
└────────────────────────────┘
```

- **Enable Face ID** → `LAContext.evaluatePolicy` fires immediately. Success or failure, this is also enrollment — proceed either way; failure just sets `biometricEnabled = false` with a toast ("You can enable this later in Settings"). On success, `biometricEnabled = true` and `unlockMethod` defaults to **Face ID Only** (§2.4).
- **Set up later** → `biometricEnabled = false`; the session gate has no biometric option and runs on device passcode alone until Face ID is turned on later in Settings.
- `biometricEnabled`/`unlockMethod` only decide *which* local auth policy the session gate uses — they never disable the gate itself. **There is no unauthenticated path into LifeVars in V1** (see §2).
- The no-recovery line stays on-screen, not a dismissible dialog — it's the single most important expectation to set for a device-only app, and it belongs where the user is already thinking about security, not buried in Settings.

### 1.4 First LifeVar

Immediately after Face ID setup (enabled or skipped), before Home:

```
┌────────────────────────────┐
│  What's something you       │
│    always forget?           │
│                             │
│ ┌─────────────────────────┐│
│ │ e.g. Audi VIN            ││
│ └─────────────────────────┘│
│                             │
│        Skip for now         │
└────────────────────────────┘
```

Typing a name and continuing drops straight into Add Step 2 (§6.2) with that name pre-filled and already classified. This single question does the onboarding's real job — getting the user to their own "oh, my VIN" moment — instead of explaining the product further. **Skip for now** → empty-state Home (§3.1).

---

## 2. Session / app unlock

This is the mechanism the coding agent should build once and reuse everywhere — not five bespoke Face ID prompts.

**Why app-open requires auth**: names and aliases are encrypted at rest, not just values (§17 in source discussion — "Social Security Number" sitting in a plaintext list on a locked screen already leaks information). So there is no surface, including Home, that can render before authentication.

### 2.1 LockScreen

Shown: on cold launch (after onboarding), and any time the app returns to foreground after having been backgrounded (default setting — see §11).

```
┌────────────────────────────┐
│                             │
│         { = }               │
│                             │
│       LifeVars               │
│                             │
│     [ Face ID prompt ]      │
│                             │
└────────────────────────────┘
```

- On appear, immediately calls `evaluatePolicy` — no button tap needed to trigger it (the screen itself *is* the prompt).
- **Success** → decrypt the name/alias index into memory (§17), mark session unlocked, show Home.
- **Failure/cancel** → stay on LockScreen:
  ```
  Couldn't verify it's you.

       [ Try Again ]
  ```
- **Biometry lockout / not enrolled** → same screen, but the retry button reads "Use Passcode" and calls `evaluatePolicy` with `.deviceOwnerAuthentication`.
- No way to reach Home, search, or any variable name without passing this screen. Full stop.

### 2.2 `requireUnlockedSession()` — the one gate

A single function, called at every point that touches a value or the decrypted index:

- Reveal (§4)
- Copy of a not-yet-revealed value
- Opening Edit on an existing item (to populate the Value field, §7)
- Export/restore backup (V1.1)

Behavior: if the session is currently unlocked, **returns immediately** — no prompt, no delay. If locked (session was never established or has since backgrounded-and-relocked), it presents the same LockScreen-style prompt inline before proceeding. This is what makes §4's "no second Face ID" true: in the normal flow the user is already unlocked from opening the app, so every subsequent reveal/edit/copy in that session is instant. The gate only re-fires after a background-triggered relock.

### 2.3 Locking

- `scenePhase → .background` while "Lock when app backgrounds" is On (default, §11) → session unlocked flag cleared immediately, decrypted in-memory index zeroed/discarded, any open RevealView/EditVariableView dismissed.
- `scenePhase → .active` after that → LockScreen (§2.1), not Home.
- If the setting is Off, the session simply persists until the app is terminated — no separate idle timeout in V1 (don't build a slider for this now; it's one toggle per §11's mockup).
- App-switcher snapshot: apply a blur/logo overlay at the `Scene` level in `sceneWillResignActive` / removed in `sceneDidBecomeActive`, regardless of the lock-on-background setting — this is presentation hygiene, separate from the auth state.

### 2.4 Unlock method

Chosen in Settings (§11); default is set automatically at Face ID enrollment (§1.3), not asked as a separate onboarding screen.

- **Face ID Only** (default once biometrics are enrolled) — Keychain access control `.biometryCurrentSet`, evaluated with `.deviceOwnerAuthenticationWithBiometrics`. No passcode fallback, ever.
- **Face ID + Device Passcode** — Keychain access control `.userPresence`, evaluated with `.deviceOwnerAuthentication`. Either unlocks the app.
- If biometrics were never enrolled ("Set up later" in §1.3), there is no Face ID Only option — the gate runs on passcode alone until Face ID is turned on from Settings.

**Trade-off to disclose at the point of choice, not bury**: `.biometryCurrentSet` is invalidated automatically by iOS the moment the user adds, removes, or re-enrolls a Face ID face — this is platform behavior, not a bug. With no passcode fallback and no backup in V1, that means **every LifeVar becomes permanently unrecoverable** the next time Face ID enrollment changes. Show this inline under the Face ID Only option: "If your Face ID settings change, your LifeVars cannot be recovered." `.userPresence` mode does not have this failure mode — a passcode change or new enrolled face doesn't affect it. Don't let a user land on the stronger mode without seeing that sentence.

---

## 3. Home

```
┌──────────────────────────────────┐
│ LifeVars                   🔒 ⚙︎ │
│                                  │
│ What do you need?                │
│ ┌──────────────────────────────┐ │
│ │ Search or ask...          🎙 │ │
│ └──────────────────────────────┘ │
│                                  │
│ YOUR VARIABLES                   │
│                                  │
│ 🚗  Audi VIN                     │
│     •••••••••••••••••            │
│                                  │
│ 🪪  Passport Number              │
│     •••••••••                     │
│                                  │
│ 🏢  EIN                          │
│     ••-•••••••                    │
│                                  │
│ ⚡  Electric Account             │
│     •••••••••••                   │
│                             ＋    │
└──────────────────────────────────┘
```

- Values are **never** shown on Home, authenticated or not — Home is an index, not a viewer. Masked preview: `•` repeated to roughly match value length, capped around 17 dots.
- List sorted by `lastAccessedAt` descending. Updates only on a *successful* reveal, not on a tap or failed auth.
- Row tap → straight into RevealView via `requireUnlockedSession()` (instant if already unlocked this session, per §2.2).
- Search filters live against name + aliases from the in-memory decrypted index (§2.1) — no additional auth needed to search once the session is unlocked, since you can't reach Home unauthenticated in the first place.
- `+` → Add flow (§5). `⚙︎` → Settings (§11). `🔒` → immediately clears the session (§2.3) and returns to LockScreen — a manual lock for handing the phone to someone else without waiting for backgrounding to trigger it.

### 3.0.1 Grouping by category (optional display mode)

A small toggle above the list ("Category") switches Home between two *display* modes — this never changes storage, only presentation:

- **Off (default)**: the flat, recency-sorted list described above — "as it is now."
- **On**: items are grouped into sections by `Category`, one section per category that actually has at least one item, ordered by the fixed `Category` case order (Identity, Vehicle, Home, Business, Insurance, Financial, Membership, Other) rather than alphabetically or by recency. Within a section, items keep the same recency order as the flat list. A category with zero items in it gets no section — no empty "MEMBERSHIP" header for someone who's never saved one.

The toggle state persists across launches (`@AppStorage`). Search still applies first — grouping organizes whatever's already been filtered, so searching while grouped only shows matching items, grouped.

### 3.1 Empty state

```
┌────────────────────────────┐
│ LifeVars                    │
│                             │
│         { = }                │
│                             │
│  Nothing to remember yet.   │
│                             │
│  Add the numbers and        │
│  details you never want     │
│  to look up again.          │
│                             │
│    [ Add a LifeVar ]        │
└────────────────────────────┘
```

`{ = }` is the app's visual motif (also the icon concept, §14) — references variables without looking like a developer tool or a security app.

### 3.2 Search

Typing `vin` filters to `Audi VIN` immediately (substring/token match, §9). Typing `insurance` can return multiple rows (`Auto Insurance Policy`, `Health Insurance Member ID`) — shown as a normal filtered list, no special disambiguation UI needed for typed search since the user picks by tapping.

No-match state:

```
┌────────────────────────────┐
│ storag                  🎙 │
│                             │
│    No match for "storag"    │
│  [ Save "storag" as new ]  │
└────────────────────────────┘
```

Tapping the suggestion opens the Add flow (§5) with the query pre-filled as the name.

Typed search narrowing to exactly one row: pressing Return (or the keyboard's search button) reveals that row the same as tapping it — this is what makes typed search converge on the same speed as voice (§4).

---

## 4. Voice interaction

Tap 🎙 → search field transforms in place:

```
┌────────────────────────────┐
│ ● Listening...              │
└────────────────────────────┘
```

`SFSpeechRecognizer`, on-device recognition only (`requiresOnDeviceRecognition = true`). If on-device recognition isn't available for the current language/device, voice retrieval is disabled entirely for that session — the mic icon shows a brief explanatory state instead. **Never silently fall back to server-side transcription**: even the query itself ("what's my social security number") is sensitive context that shouldn't leave the device, independent of whether the value ever would.

On end-of-speech (~1.2s silence) or manual stop, briefly show the transcription:

```
What's my Audi VIN?
```

then strip conversational filler and run it through the matcher (§9.2):

- **Single confident match** → `requireUnlockedSession()` immediately, no intermediate screen. This is the whole point of voice — say it, see the value.
- **Multiple matches** → disambiguation list (§10), auth happens *after* the user picks one, not before.
- **No match** → same no-match card as §3.2, transcript pre-filled as name.

Mic permission denied: inline text under the search bar ("Enable microphone access in Settings"), mic icon disabled but visible.

No text-to-speech, ever. LifeVars never speaks a value back.

---

## 5. Reveal screen

```
             🚗

          Audi VIN

     WAUZZZ8V4JA123456


          [ Copy ]


      Hides in 18 seconds
```

- Value in monospaced type; `minimumScaleFactor` so unusually long values shrink to fit one line rather than wrapping awkwardly.
- Countdown starts at 30s (default, configurable in Settings §11 — 10/20/30/60), subdued — plain text ticking down ("28 seconds" → "27" → "26"), no progress ring or red flash. 30s rather than 20s because the user is already inside an authenticated session; the timer is a tidiness measure for an unattended screen, not the primary security boundary — that's backgrounding (§2.3), which hides the value immediately regardless of where the countdown is.
- **On timeout**: re-mask in place, don't dismiss the screen:
  ```
  Audi VIN

  •••••••••••••••••

  [ Reveal Again ]
  ```
  `Reveal Again` → `requireUnlockedSession()` (instant if session still unlocked, per §2.2) → re-reveals with a fresh countdown.
- **Copy**: explicit button only in V1 (tapping the value itself is deliberately inert — avoids accidental copies). Shows "✓ Copied" for ~1.5s. Sets `UIPasteboard` with `expirationDate` 60s out (native API, not a custom timer).
- Dismiss (✕ / swipe down) → Home, no confirmation (nothing destructive occurred).
- Screen-recording guard: `UIScreen.capturedDidChangeNotification` — if recording is active while this screen is visible, blank the value area with "Value hidden while screen recording is active."

---

## 6. Adding a LifeVar

Two-step wizard, not a single dense form — the suggestions are what remove the "what do I even call this" friction.

### 6.1 Step 1 — name

```
Add a LifeVar

What do you want to remember?

┌──────────────────────────────┐
│ e.g. Audi VIN                │
└──────────────────────────────┘

Suggestions

Social Security Number
Passport Number
Driver's License
VIN
Insurance Policy
Electric Account
EIN

                Continue
```

Suggestions are static, from the category list in PLAN.md §6. Tapping one fills the text field and classification (§9) runs immediately (icon + aliases resolved before Step 2 even opens). Typing a custom name also runs classification on blur/debounce, falling back to Other/🔖 with no aliases if nothing matches.

### 6.2 Step 2 — value + confirm name

```
🚗 Vehicle ⌄

Enter the value

┌──────────────────────────────┐
│ WAU...                       │
└──────────────────────────────┘

Name

┌──────────────────────────────┐
│ Audi VIN                     │
└──────────────────────────────┘

               Save
```

- Category header is a **dropdown**, not a static label — defaults to the auto-classified result, but the user can override it directly from the menu (all `Category` cases listed). Once manually picked, that choice sticks even if the user edits the Name field afterward on this same screen — auto-classification only ever supplies a *default*, never overwrites an explicit choice. Aliases stay tied to name-based classification regardless of the category picked, since they're about likely phrasings of the name, not the category label.
- Header shows the resolved category label ("VIN"); Name field is pre-filled with what was typed/tapped in Step 1 but editable — this is where "Audi VIN" vs "Tesla VIN" gets disambiguated for users with more than one.
- Value field: monospaced, masked by default with an eye toggle to reveal-while-typing.
- **Duplicate name** (case-insensitive match against an existing name or alias): inline error on Save, block until resolved.
- **Free tier gate**: on Save, if `items.count >= 3` and not Pro → present PaywallView instead of saving (§11.1). Checked at Save so the compose flow itself is never blocked.
- Save with empty Name or Value → Save stays disabled, no error state needed.

No per-item sensitivity/security picker in this flow — see §8.

---

## 7. Editing

Swipe actions on a Home row (native feel, preferred over long-press):

```
Audi VIN
[ Edit ]  [ Delete ]
```

**Delete** → native `.confirmationDialog`: "Delete Audi VIN? This can't be undone." Delete / Cancel.

**Edit** opens:

```
Edit LifeVar

Name
Audi VIN

Value
•••••••••••••••••

Aliases
VIN
Car VIN
Vehicle VIN
[ Add Alias ]

Save
```

- Value field opens masked. Revealing it to edit calls `requireUnlockedSession()` (§2.2) — in the normal flow this resolves instantly since you're already in an unlocked session to have reached Edit at all; it only prompts if the session has since relocked (e.g. very slow user, or backgrounded and returned via some other path).
- Aliases shown as removable chips + Add Alias field, seeded from the auto-generated list (§9) and freely editable — this is correction, not required data entry.
- Save re-runs the duplicate-name check from §6.2.

---

## 8. Sensitivity / security level

**No per-item setting in V1.** Every LifeVar is protected identically — the product's predictability ("every LifeVar is protected") is worth more than granular control right now. Don't add a Sensitivity picker to the Add/Edit UI at all; a stub field a user can't act on is worse than no field. Revisit a `standard` / `always Face ID` split in V1.1 only if the always-authenticate model proves annoying in practice.

---

## 9. Classification & matching

### 9.1 Auto-classification (on name entry)

Local, deterministic keyword lookup — no network call, no ML model. A static ordered table, first match wins:

```
"Audi VIN" / "vin" / "vehicle number"     → 🚗 Vehicle,   aliases: [VIN, Car VIN, Vehicle VIN]
"EIN" / "employer id"                      → 🏢 Business,  aliases: [EIN, Tax ID]
"SSN" / "social security"                  → 🪪 Identity,  aliases: [SSN, Social]
"passport"                                 → 🪪 Identity,  aliases: [Passport, Passport Number]
"electric account" / "power account"       → ⚡ Home,      aliases: [Electric, Power Account]
"hvac filter" / "air filter"               → 🏠 Home,      aliases: [Filter Size, Air Filter]
(no match)                                 → 🔖 Other,     aliases: []
```

Mechanical sub-phrase aliasing only applies when the name matched a known category above (e.g. "Audi VIN" gets `VIN`/`Car VIN`/`Vehicle VIN` because "vin" hit the table). For names that fall through to Other, don't auto-generate combinations — an unclassified name like "Mom's Storage Unit Access Code" gets `aliases: []` by default, editable by the user in §7. A false-positive match on a wrong item is worse than asking the user to say the name they actually gave it; mechanically inventing phrasings for text we don't understand raises exactly that risk without evidence it helps.

This classification result is always just a *default* — §6.2 and §7 both let the user override the category directly from a dropdown. "Custom" was renamed to "Other" throughout (code and UI) once category became a user-facing, user-editable concept rather than pure internal metadata — "custom" reads oddly as a thing someone picks for themselves from a menu.

Formatting-on-display (SSN → `123-45-6789`, EIN → `12-3456789`) is a pure display transform in RevealView, driven by a `ValueFormat` enum carried in the encrypted metadata (§14) rather than re-derived from category at display time; the stored value is never mutated, and Copy always copies the raw unformatted value.

### 9.2 Matching (search text or voice transcript → item)

One function, used by both:

1. Normalize (lowercase, strip punctuation).
2. Strip conversational filler — a fixed stop-phrase list (`what's`, `what is`, `whats`, `my`, `show me`, `give me`, `tell me`, `can you`, `number`, `please`, `for`, `the`) removed as whole words, not substrings. This is what turns "Can you give me the VIN for my Audi?" into `vin audi` before matching even starts — voice output is conversational, LifeVar names aren't, and this one preprocessing step closes that gap without any ML.
3. Exact match against name or alias → confidence: exact.
4. Substring match either direction → confidence: partial.
5. Token match: all remaining words in the query appear somewhere in name/aliases, any order.
6. If exactly one candidate at the top confidence tier → single match (auto-proceed, §4/§3.2). Otherwise → disambiguation (§10).

No fuzzy/edit-distance matching in V1 — aliases carry that load; add Levenshtein in V1.1 only if the alias system proves insufficient in practice.

---

## 10. Multiple matches

```
Which VIN?

Audi VIN

BMW VIN
```

Tap one → `requireUnlockedSession()` → Reveal. **Auth happens after selection, not before the list is shown** — don't burn a biometric prompt before the user has even said which one they mean.

---

## 11. Settings

```
Settings

SECURITY
Unlock Method                Face ID Only ›
Auto-hide                    30 seconds
Lock when app backgrounds    On

LIFEVARS PRO
3 of 5 used · Upgrade →

APPEARANCE
System / Light / Dark

ABOUT
Privacy
Security
About LifeVars
Version 1.0
```

- **Unlock Method**: opens the two-option picker from §2.4 (Face ID Only / Face ID + Device Passcode), with the invalidation trade-off caption shown at the point of choice. Only shown once biometrics are enrolled; otherwise this row is absent and the app runs on passcode alone.
- **Auto-hide**: the Reveal-screen countdown duration (§5), default 30s. A simple picker (10s / 20s / 30s / 60s) — no need for a continuous slider.
- **Lock when app backgrounds**: drives §2.3. Default On.
- **No Encrypted Backup / Restore rows in V1.** Export/import is real V1.1 work (PLAN.md §9/§15) that doesn't exist yet — a settings row implies working functionality, and a "Coming soon" label on a data-recovery feature risks a user assuming they're covered when they aren't. Add the rows in V1.1 when they do something; the settings list can grow later at near-zero cost.
- **LifeVars Pro**: shows `X of 3 used` on free tier, opens PaywallView (§11.1) on tap; shows "Pro — Unlimited" with no tap target once purchased.
- **About → Privacy/Security**: static screens explaining local-only storage and the encryption model in plain language — this is the app's actual marketing claim, worth getting right, not boilerplate legal text.

### 11.1 Paywall

```
      LifeVars Pro

   Unlimited LifeVars
   Siri integration (soon)
   Encrypted backup (soon)

    [ Unlock — $9.99 ]
       one-time

     Restore Purchase
```

Voice retrieval, search, and Face ID protection are part of the **free** experience — the "ask and get an instant answer" loop is the entire pitch, and paywalling it means a free user never sees what LifeVars actually is. Free tier is capped at 3 items total, not 3 voice queries or 3/month. Pro removes the item cap and unlocks features as they ship (Siri, backup are both V1.1 — listed here as roadmap, not present functionality, hence "(soon)"). StoreKit 2, single non-consumable, per PLAN.md §17. Limit checked at Save time (§6.2).

---

## 12. App icon

Original guidance: avoid padlock / shield / key / fingerprint — every security app uses those, and LifeVars' security should be an attribute, not the brand — and use the `{ = }` motif from the empty state (§3.1) instead. That version was built first (hand-rendered, `Assets.xcassets/AppIcon.appiconset`) and works as a fallback.

**Deviation, by direct request**: the shipped icon is a fingerprint/shield "V" monogram, which is exactly the imagery this section originally said to avoid. Flagged, not silently overridden — worth a second look at actual Home Screen (60pt) and Settings-row (29pt) scale, since fine ridge linework and glow effects are the kind of detail that tends to blur out at those sizes; not yet confirmed on a real device or Simulator Home Screen.

---

## 13. Siri / App Intents (V1 stretch)

Build only after the core loop (step 9 in §16) is solid — don't start here.

```
"Siri, ask LifeVars for my Audi VIN"
        │
        ▼
  query = "Audi VIN" → matched against name/alias index
        │
        ▼
  LifeVars needs to authenticate you.
        [ Open LifeVars ]
        │
        ▼
  Open → LockScreen/session gate (§2) → Reveal
```

Hard rule for `FindLifeVarIntent`, not a nice-to-have: **it never returns the decrypted value to Siri, ever** — no spoken result, no Siri-rendered snippet containing the value. It can at most hand back a match confirmation and deep-link into the app to finish the reveal through the normal gate.

§19.5 adds a **second, separate intent** (`CheckLifeVarIntent`) that deliberately breaks this rule — on direct request, and narrowly. Both intents stay registered; `FindLifeVarIntent` remains the "open the app properly" path.

---

## 14. Data model

```swift
struct LifeVar {
    let id: UUID
    var encryptedMetadata: Data   // AES-GCM ciphertext of LifeVarMetadata below
    var encryptedValue: Data      // AES-GCM ciphertext of the raw value string
    var emergencyPayload: Data?   // §19.2 — sealed under a DIFFERENT, weaker-gated key; nil for most items
    var createdAt: Date
    var updatedAt: Date
    var lastAccessedAt: Date?
}

// Serialized (e.g. JSON) and encrypted together as encryptedMetadata — a category
// like "identity" sitting in plaintext next to "financial" and "business" rows is
// itself information about what someone stores here, so it doesn't get a free pass.
struct LifeVarMetadata: Codable {
    var name: String
    var aliases: [String]
    var category: Category?
    var format: ValueFormat?          // §9.1 — display-only, never mutates the stored value
    var expiresAt: Date?              // §19.1
    var deleteOnExpiration: Bool      // §19.1 — "temporary" items vs. items that just notify
    var isEmergencyAccessible: Bool   // §19.2 — flag only; the readable copy lives in emergencyPayload above
    var isPinned: Bool                // §19.4 — at most one true at a time, enforced in LifeVarStore
}

enum Category: String, Codable {
    case identity, vehicle, home, business, insurance, financial, membership, other
}

enum ValueFormat: String, Codable {
    case ssn, ein
}
```

On-disk, nothing is plaintext except `id` and the date fields — none of which are sensitive on their own (dates don't reveal *what* a record is). Category is encrypted metadata, not a storage-level folder — every item still lives in one flat store regardless of category. It does drive an optional *display* grouping in Home (§3) and the row icon, and the user can pick it directly rather than only ever accepting the auto-classified default (§6.2, §7).

`isPinned`'s corresponding item *id* (never its name/category/value) is also republished in the clear to a shared App Group store for the Lock Screen widget to read (§19.4) — the same "id alone is safe" reasoning as above, just crossing a process boundary instead of sitting on disk.

---

## 15. Security architecture — do not improvise this part

One key, one place it's protected, one way it's evaluated. Not a menu of options for the coding agent to pick from.

### 15.1 Key and encryption

- On first launch, generate one random 256-bit key (`SymmetricKey(size: .bits256)`, CryptoKit) — the **data encryption key (DEK)**. This single key encrypts every `encryptedMetadata` and `encryptedValue` blob via `AES.GCM.seal`. No per-item keys, no key hierarchy — there's exactly one thing to protect.
- Store the DEK as a single Keychain item with `SecAccessControl` flags set per the chosen unlock method (§2.4): `.biometryCurrentSet` for Face ID Only, `.userPresence` for Face ID + Passcode, accessibility `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. This is the *entire* auth mechanism — don't also build a separate manual `LAContext.evaluatePolicy()` prompt layered on top of it; fetching the DEK from Keychain is what triggers the system Face ID/passcode UI. Two overlapping auth prompts is the improvisation this section exists to prevent.
- Session semantics (§2.2's `requireUnlockedSession()`): create one `LAContext` per session, pass it via `kSecUseAuthenticationContext` on the Keychain fetch of the DEK. The first fetch triggers the system prompt; the same `LAContext` reused on later Keychain reads within the session does not re-prompt, which is exactly "auth once, use it until locked." Call `context.invalidate()` on lock (§2.3) so the next fetch prompts again.
- Hold the DEK in memory only for the session; on lock, drop the reference (Swift's ARC is sufficient here — don't hand-roll memory zeroing for a value that's about to be deallocated anyway).

### 15.2 Edge cases — the part most likely to get improvised wrong

- **Face ID enrollment changes** (Face ID Only mode, `.biometryCurrentSet`): iOS invalidates the Keychain item *permanently* the moment the user adds, removes, or re-enrolls a face. The next unlock attempt fails with a distinct Keychain error, not a wrong-auth error — detect it and show a dedicated message ("Your device's Face ID settings changed. This can't be undone — LifeVars data protected under Face ID Only cannot be recovered without a backup.") rather than looping the user on a retry button that will never succeed. This is the documented cost of the stronger mode (§2.4), not a bug to work around.
- **Device passcode removed entirely**: iOS invalidates Keychain items behind any biometric/passcode access control when the passcode itself is removed (Face ID requires a passcode to exist at all). Same permanent-loss consequence. Not worth a proactive check at every launch, but worth a one-time launch-time check for "no passcode set" so the failure mode is explained rather than silent.
- **Keychain item missing/corrupted** (rare, but happens after OS-level Keychain resets): treat as "cannot decrypt," not a crash — show the same clear, distinct error rather than an infinite retry loop.
- **Reinstall**: uninstalling LifeVars deletes the app's local database (standard sandbox deletion) regardless of what happens to the Keychain item. Reinstalling always starts empty. This is exactly why the no-recovery warning in onboarding (§1.3) matters — it's not a hypothetical.
- **Restore to a new/wiped device from iCloud/iTunes backup**: Keychain items with `.ThisDeviceOnly` accessibility never restore to a different device by design — so if the local database file *did* restore via a normal app-data backup, it would land on the new device with no key able to decrypt it, which reads as silent corruption. Avoid that state entirely: mark the local database file `isExcludedFromBackup = true`. A device restore should leave LifeVars empty, not full of undecryptable ciphertext.

---

## 16. V1 development order

1. SwiftUI shell + navigation skeleton (§0)
2. `LifeVar` model + local encrypted store
3. Keychain key management (§15)
4. Face ID/passcode session gate (§2) — LockScreen + `requireUnlockedSession()`
5. Add/Edit/Delete (§6, §7) — CRUD working end to end behind the gate
6. Home + search (§3)
7. Reveal screen (§5)
8. Classification + matching (§9, §10)
9. Local voice transcription (§4)
10. Auto-hide + background locking polish (§2.3, §5)
11. Clipboard handling (§5)
12. Settings (§11) + Paywall
13. Siri/App Intents (§13, stretch — skip if it threatens the timeline)
14. Accessibility pass (Dynamic Type on the Reveal value, VoiceOver labels that don't read masked dots as literal characters)
15. Security review
16. TestFlight

Do not start with Siri or animation polish. Prove `ADD → ENCRYPT → LOCK → UNLOCK → SEARCH → REVEAL` first (step 7 is where it starts feeling like the real product).

---

## 17. V1 acceptance test

The definition of done:

1. Install. Add `Audi VIN = WAU123456789`.
2. Close LifeVars. Reopen → LockScreen, not Home.
3. Face ID → Home.
4. Tap mic, say "What's my Audi VIN?"
5. Within ~1 second: `Audi VIN / WAU123456789 / Copy` — no second Face ID prompt.
6. Close the app. Reopen → locked again.

If that feels instantaneous and polished, V1 is complete. The app should remain almost suspiciously small — that's the advantage.

---

## 18. Explicit non-goals for V1

Per PLAN.md §13/§16: no encrypted backup/export *functionality* (rows exist per §11, wiring is V1.1), no sharing/family, no account/login screen, no server of any kind. Siri (§13) ships only if it stays simple — cut it before cutting the security rule that gates it.

Apple Watch was originally a non-goal here too; built anyway as a post-plan addition (§19.3) at direct request.

---

## 19. Post-plan additions

Features built after the original 16-step plan (§16) closed out, in response to direct product asks. Each follows the same security invariants (§ top of doc) as everything else — no new exceptions except where §19.2 says so explicitly.

### 19.1 Expiration & temporary items

Any LifeVar can carry an optional `expiresAt`. Two independent behaviors branch on it:

- **Notify only** (`deleteOnExpiration == false`, the default when `expiresAt` is set): a local notification fires ~90 days before `expiresAt` (or immediately if less than 90 days out) with generic, non-identifying copy ("Something you saved is expiring soon — open LifeVars to check.") — never the item's name, matching the never-leak-plaintext invariant. The item itself is untouched; this is a reminder, not an action.
- **Temporary** (`deleteOnExpiration == true`, e.g. a hotel key code good for a day): no notification. Instead the item is silently deleted the next time the app is opened after `expiresAt` passes — an opportunistic sweep on every unlock (§2.2), not a background task or server, since there's no server. If nothing expired, the sweep is a no-op.

Configured in Add/Edit via a simple picker (Never / 1 Day / 1 Week / Custom Date) plus a "delete automatically when expired" toggle shown once any expiration is set. RevealView shows a caption reflecting which mode applies ("Expires …" vs. "Deletes …").

### 19.2 Emergency Info

A deliberate, narrow, disclosed exception to "Face ID gates everything" (top-of-doc invariants) — modeled on Apple's own Medical ID trade-off: some information is more useful to a first responder unauthenticated than it is protected. Per-item opt-in only, off by default.

- A **second Keychain key**, independent of the DEK (§15.1), with standard `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` protection and **no** biometric/passcode access control. This is what makes LockScreen-reachable-without-Face-ID access possible without weakening the real DEK's protection for anything else.
- Opting an item in seals a minimal shadow copy (`{name, value}` only — no aliases, category, or format) under this key, stored in `LifeVar.emergencyPayload`.
- `LockScreenView` gets an "Emergency Info" button, **outside the session gate entirely**, opening a dedicated screen that lists only opted-in items with a persistent "Visible without Face ID" banner.
- Deliberately **no** screen-recording guard on this one screen (unlike Reveal, §5) — an emergency responder may need to show it to someone else.
- The onus is on the user to choose narrowly (blood type, allergies, an emergency contact, an insurance member ID) — the UI warns against opting in anything sensitive, but doesn't structurally prevent it. That's the accepted trade-off, not an oversight.

### 19.3 Apple Watch

Thin-client relay, not a second copy of the vault. The Watch app never holds a DEK or any decrypted data — every "ask" is a live round-trip to the phone, which must already be unlocked (§2). Chosen deliberately over giving the Watch its own key: safer, simpler to audit, and doesn't need a physical Watch present to validate a cross-device key-transfer protocol that a relay design avoids needing in the first place.

```
Watch: "Insurance policy."
        │  WatchConnectivity message: {"query": "insurance policy"}
        ▼
Phone (already unlocked): same Matcher (§9.2) as typed search/voice/Siri
        │
        ▼
Watch: name + value + [Done]  — no scrolling, no folders
```

If the phone is locked, the Watch shows "Open LifeVars on iPhone first" rather than attempting any auth of its own — there is no Watch-side auth flow, by design.

### 19.4 Lock Screen & Control Center widgets

A `WidgetKit` extension, embedded the same way the Watch app is. Two pieces:

- **Pinned Variable** (Lock Screen accessory widget): at most one LifeVar can be pinned at a time (configured via a toggle in Add/Edit; pinning a new one silently unpins the old one). The widget is a *shortcut*, never a *display* — it shows a generic locked-icon glyph and "Pinned"/"Not Set", never the item's name, category, or value. It learns only the pinned item's id, published across an App Group boundary the same way `id` is already considered safe to store in the clear on disk (§14). Tapping it opens the app and still runs the full Face ID session gate (§2) before RevealView shows anything — the widget itself proves nothing and decrypts nothing.
- **Ask LifeVars** (Control Center control, iOS 18+): one tap opens the app straight into Home with the mic already listening — same `openAppWhenRun` pattern as the Siri App Intent (§13): the control's action runs in the extension process, which structurally cannot hold a DEK, so all it can do is flag "start listening" for the main app to pick up once it's actually open and unlocked.

### 19.5 Headless Siri check (`CheckLifeVarIntent`) — an explicit exception, not a precedent

By direct request: "Ask LifeVars to check my Audi VIN" → Face ID prompts as a system overlay, without the app ever opening → the value shows once as an inline Siri result. This is a **second, separate** App Intent from `FindLifeVarIntent` (§13), with `openAppWhenRun = false`, and it deliberately breaks §13's "never returns a decrypted value to Siri" rule — that rule still governs `FindLifeVarIntent`, which stays as the "open the app properly" path.

What makes this an acceptable, bounded exception rather than a hole in the security model:

- **Its own momentary auth, not the app's session.** `perform()` creates its own throwaway `LAContext` and fetches the DEK straight from `KeychainDEKStore` — the same Keychain-gated fetch that *is* the auth everywhere else (§15.1) — never touching `SessionManager`. Nothing persists after `perform()` returns; there's no session to leave unlocked.
- **Never a notification.** The result renders as a Siri snippet (`LifeVarSnippetView`, `AppIntents`+`SwiftUI` cross-import's `.result(view:)`) shown once as part of the response the user just spoke. A local notification was explicitly considered and rejected: it would show on the Lock Screen by default (no unlock needed to read it), persist in Notification Center until manually cleared, and can mirror to other Apple-ID-linked devices via Handoff — a strictly worse leak surface than a one-time Siri response.
- **Decrypt logic is shared, not duplicated.** `LifeVarLookup.lookup()` (`Data/LifeVarLookup.swift`) is the same decrypt-and-`Matcher.match` shape `LifeVarStore.reload()` uses, factored out so both build a `DecryptedIndexEntry` the same way (`DecryptedIndexEntry(id:metadata:)`) — a fix to the matcher applies to both call sites, not just one.
- **Named caveat, not a hidden one**: the Siri snippet is system UI whose on-screen lifetime LifeVars doesn't control, unlike `RevealView`'s auto-hide/no-screen-recording guard (§5). And since Face ID authenticates *whoever's face is in front of the phone*, not *the request's origin*, this works the same whether the phone is locked or not — worth knowing before relying on it for something highly sensitive.
