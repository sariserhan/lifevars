import Foundation
import WatchConnectivity

/// The Apple Watch companion is a thin client — it never holds a DEK and
/// never decrypts anything itself. It sends a plain query string over
/// WatchConnectivity's encrypted device-pairing channel, and this class
/// answers it using the exact same session gate (§2) and matcher (§9.2) as
/// everything else in the app. This is a deliberately different, simpler,
/// and more auditable design than giving the Watch its own copy of the
/// encryption key: the crypto never leaves the phone, so there's no second
/// key-transfer protocol to get wrong.
///
/// If the phone's session isn't unlocked, the watch is told so and shows
/// "Open LifeVars on iPhone" — there's no way for the watch to trigger
/// Face ID on the phone remotely, and that's deliberate; "the watch is on
/// wrist and the phone is already unlocked" is the trust model, mirroring
/// how Apple Pay/Wallet trust an unlocked, on-wrist Watch without a second
/// biometric prompt.
final class PhoneConnectivitySession: NSObject, WCSessionDelegate {
    private let session: SessionManager
    private let store: LifeVarStore

    init(session: SessionManager, store: LifeVarStore) {
        self.session = session
        self.store = store
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ wcSession: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let query = message["query"] as? String else {
            replyHandler(["status": "error"])
            return
        }
        Task { @MainActor [weak self] in
            let response = await self?.handle(query: query) ?? ["status": "error"]
            replyHandler(response)
        }
    }

    @MainActor
    private func handle(query: String) async -> [String: Any] {
        guard session.isUnlocked else {
            return ["status": "locked"]
        }
        let matches = Matcher.match(query: query, in: store.items)
        guard let topConfidence = matches.first?.confidence else {
            return ["status": "notFound"]
        }
        let topMatches = matches.filter { $0.confidence == topConfidence }.map(\.entry)
        guard topMatches.count == 1, let match = topMatches.first else {
            return ["status": "ambiguous", "candidates": topMatches.map(\.name)]
        }
        do {
            // §15.1 — decrypts only the single matched record, same as any other reveal.
            let value = try store.revealValue(id: match.id)
            let displayValue = match.format?.apply(to: value) ?? value
            return ["status": "ok", "name": match.name, "value": displayValue]
        } catch {
            return ["status": "error"]
        }
    }
}
