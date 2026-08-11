import SwiftUI
import SwiftData

@main
struct QuickVarsApp: App {
    @StateObject private var session: SessionManager
    @StateObject private var store: QuickVarStore
    @StateObject private var storeManager = StoreManager()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(UserSettings.Keys.appearance) private var appearanceRaw = AppearanceOption.system.rawValue
    private let modelContainer: ModelContainer
    private let watchSession: PhoneConnectivitySession

    init() {
        let container = Persistence.makeContainer()
        modelContainer = container
        let sessionManager = SessionManager()
        let quickVarStore = QuickVarStore(modelContext: container.mainContext, session: sessionManager)
        _session = StateObject(wrappedValue: sessionManager)
        _store = StateObject(wrappedValue: quickVarStore)
        // Apple Watch relay (Connectivity/PhoneConnectivitySession.swift) —
        // thin client, never holds a key, only ever asks this phone process.
        watchSession = PhoneConnectivitySession(session: sessionManager, store: quickVarStore)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(session)
                    .environmentObject(store)
                    .environmentObject(storeManager)
                    .preferredColorScheme((AppearanceOption(rawValue: appearanceRaw) ?? .system).colorScheme)

                // §2.3 — app-switcher snapshot hygiene, independent of the
                // auth state: covers whatever's on screen (Home, Reveal,
                // Add/Edit, even the lock screen itself) the moment the app
                // stops being frontmost, not just once it's backgrounded.
                if scenePhase != .active {
                    AppSwitcherOverlay()
                }
            }
            // Lock Screen "pinned variable" widget's tap target — see
            // Widgets/PendingDeepLink.swift. HomeView drains this the same
            // way it drains a pending Siri query.
            .onOpenURL { url in
                guard url.scheme == "quickvars", url.host == "reveal",
                      let idString = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                          .queryItems?.first(where: { $0.name == "id" })?.value,
                      let id = UUID(uuidString: idString) else { return }
                PendingDeepLink.shared.revealItemID = id
            }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            session.handleScenePhaseChange(newPhase)
        }
    }
}
