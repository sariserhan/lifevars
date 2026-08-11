import WidgetKit
import SwiftUI

@main
struct QuickVarsWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PinnedVariableWidget()
        if #available(iOS 18.0, *) {
            AskQuickVarsControl()
        }
    }
}
