import ChunUI
import SwiftUI
import UIKit

/// The single theme entry point. Playback surfaces keep native AVKit behavior.
@MainActor
enum PiliChunUIBridge {
    static func configure(tint: Color = AppThemeTintColor.color(for: AppThemeTintColor.defaultHex)) {
        var colors = CCColors.default
        colors.primary = tint
        colors.ring = tint
        colors.info = tint
        var strings = CCStrings()
        strings.cancel = "取消"
        strings.confirm = "确定"
        strings.done = "完成"
        strings.save = "保存"
        strings.discard = "放弃更改"
        strings.retry = "重试"
        strings.loading = "加载中…"
        strings.loadFailed = "加载失败"
        strings.empty = "暂无内容"
        strings.loadingMore = "加载更多…"
        strings.noMoreData = "没有更多了"
        strings.loadMore = "加载更多"
        strings.appName = "哔哩哔哩"
        strings.unsavedTitle = "尚未保存"
        strings.unsavedMessage = "要保存本次修改吗？"
        strings.keepEditing = "继续编辑"
        ChunUI.configure(colors: colors, strings: strings)
        ChunUI.sheetPresentHook = { host, _ in PiliPresentation.configureSheet(host) }
    }

    static func attach(to scene: UIWindowScene?) {
        guard let scene else { return }
        CCToastWindow.shared.attach(to: scene)
        CCAlertWindow.shared.attach(to: scene)
    }
}

extension AppTab {
    var pikaIcon: String {
        switch self {
        case .home: "home-simple"
        case .dynamic: "notification-bell-on"
        case .live: "playlist-play"
        case .mine: "user-square"
        case .search: PikaIcon.Name.search
        }
    }
}
