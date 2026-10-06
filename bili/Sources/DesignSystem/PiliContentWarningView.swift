import SwiftUI

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
                Label(title.isEmpty ? detail : title, systemImage: "info.circle")
                if !title.isEmpty, !detail.isEmpty, title != detail { Text(detail) }
                if let url, ["http", "https"].contains(url.scheme ?? "") { AppLinkButton(url: url) { Text("查看说明") } }
            }.font(.caption).foregroundStyle(.secondary).padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
