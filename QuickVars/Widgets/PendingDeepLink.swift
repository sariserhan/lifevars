import Foundation

/// Bridge for the Lock Screen "pinned variable" widget's tap target
/// (`quickvars://reveal?id=...`, handled via onOpenURL in QuickVarsApp) —
/// in-process only, since by the time onOpenURL runs, the app is already the
/// process holding this value. Never anything but an id; HomeView looks up
/// the decrypted entry itself, same as any other row tap.
final class PendingDeepLink {
    static let shared = PendingDeepLink()
    private init() {}
    var revealItemID: UUID?
}
