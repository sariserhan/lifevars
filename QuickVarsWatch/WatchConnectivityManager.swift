import Foundation
import WatchConnectivity

/// The Watch never holds a key or a decrypted value at rest — every ask is
/// a fresh round trip to the phone (PhoneConnectivitySession.swift), which
/// does the actual matching and decryption. This class is a thin
/// request/response wrapper around that, nothing more.
@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    enum State {
        case idle
        case asking
        case result(name: String, value: String)
        case locked
        case notFound
        case ambiguous([String])
        case unreachable
        case error
    }

    @Published private(set) var state: State = .idle

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func ask(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard WCSession.default.isReachable else {
            state = .unreachable
            return
        }
        state = .asking
        WCSession.default.sendMessage(["query": trimmed]) { [weak self] reply in
            Task { @MainActor in self?.handle(reply) }
        } errorHandler: { [weak self] _ in
            Task { @MainActor in self?.state = .error }
        }
    }

    func reset() {
        state = .idle
    }

    private func handle(_ reply: [String: Any]) {
        switch reply["status"] as? String {
        case "ok":
            guard let name = reply["name"] as? String, let value = reply["value"] as? String else {
                state = .error
                return
            }
            state = .result(name: name, value: value)
        case "locked":
            state = .locked
        case "notFound":
            state = .notFound
        case "ambiguous":
            state = .ambiguous(reply["candidates"] as? [String] ?? [])
        default:
            state = .error
        }
    }
}
