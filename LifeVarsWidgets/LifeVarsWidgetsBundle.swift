import WidgetKit
import SwiftUI

@main
struct LifeVarsWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PinnedVariableWidget()
        if #available(iOS 18.0, *) {
            AskLifeVarsControl()
        }
    }
}
