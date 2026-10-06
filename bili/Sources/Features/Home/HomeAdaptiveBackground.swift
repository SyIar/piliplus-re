import SwiftUI
import ChunUI

extension HomeFeedLayout {
    var homeFeedBackground: Color {
        self == .borderedSingleColumn
            ? Color(.systemGroupedBackground)
            : Color.cc.background
    }
}
