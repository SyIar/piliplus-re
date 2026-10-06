import SwiftUI
import ChunUI

struct PiliContentWarningView: View {
    let title: String
    var detail = ""
    var url: URL? = nil
    var video = false
    @AppStorage("piliplus.display.videoWarnings") private var videoWarnings = true
    @AppStorage("piliplus.display.dynamicWarnings") private var dynamicWarnings = true
    var body: some View {
        if (video ? videoWarnings : dynamicWarnings), !title.isEmpty || !detail.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                PiliLabel(title.isEmpty ? detail : title, systemImage: "info.circle")
                if !title.isEmpty, !detail.isEmpty, title != detail { Text(detail) }
                if let url, ["http", "https"].contains(url.scheme ?? "") { AppLinkButton(url: url) { Text("查看说明") } }
            }.piliFont(.sm).foregroundStyle(.secondary).padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .piliGlassCard(radius: 10)
        }
    }
}
