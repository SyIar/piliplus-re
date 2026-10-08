import SwiftUI

struct VideoDetailActionStripIconLabel: View {
    let title: String
    let systemImage: String
    let foregroundStyle: Color

    var body: some View {
        VideoDetailActionLabel(title: title, systemImage: systemImage)
            .foregroundStyle(foregroundStyle)
    }
}
