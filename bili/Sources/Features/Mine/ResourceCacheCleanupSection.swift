import SwiftUI

struct ResourceCacheCleanupSection: View {
    let performClear: (@escaping () async -> Void) -> Void

    var body: some View {
        Section("清理") {
            row("播放源") { await ResourceCacheCenter.clearPlayURL() }
            row("图片") { await ResourceCacheCenter.clearImages(includeDisk: true) }
            row("接口数据") { await ResourceCacheCenter.clearAPI() }
            row("播放片段") { await ResourceCacheCenter.clearProgressiveMedia() }
            row("字幕与弹幕") { await ResourceCacheCenter.clearSubtitlesAndDanmaku() }
            row("全部缓存") { await ResourceCacheCenter.clearAll() }
        }
    }

    private func row(_ title: String, action: @escaping () async -> Void) -> some View {
        PiliSettingAction(title: title) {
            Button("清理", role: .destructive) { performClear(action) }
                .accessibilityLabel("清理\(title)")
        }
    }
}
