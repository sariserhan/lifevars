import SwiftUI

/// SPEC.md §2.3 — shown the instant the scene stops being active, covering
/// the app-switcher snapshot. Deliberately has nothing to do with auth state:
/// it hides values, list content, and in-progress form text alike, since all
/// of those are things a snapshot could otherwise leak.
struct AppSwitcherOverlay: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("{ = }")
                    .font(.system(size: 48, weight: .light, design: .monospaced))
                Text("LifeVars")
                    .font(.title2.bold())
            }
        }
    }
}
