import SwiftUI

struct PiliSettingsSearchView: View {
    let onOpenRoute: (MineOverlayRoute) -> Void
    @State private var query = ""
    private let entries: [(String, String, MineOverlayRoute)] = [
        ("界面显示", "主题 颜色 蓝色 液态玻璃 外观 深色 字体 导航 首页标签 高刷新率 120Hz", .interfaceSettings),
        ("首页与搜索", "推荐 热门 排行 搜索 历史 默认 关键词 布局 双列 卡片", .homeAndSearchSettings),
        ("播放偏好", "自动播放 解码 硬件 HDR 杜比 色彩 音质 画质 CDN 缓冲 全屏 方向 比例 字幕 翻译 手势 触感 长按 倍速 弹幕 合并 跳过 空降 助手 SponsorBlock MetalFX", .playbackSettings),
        ("内容过滤", "黑名单 屏蔽 关键词 UP主 时长 推荐 相关视频 充电 广告 带货 评论", .contentFilterSettings),
        ("隐私", "无痕 游客 历史 检查 可见性 阅读 Cookie 隐私", .privacySettings),
        ("多账号设置", "账号 登录 切换 播放 互动 评论 阅读 身份", .multiAccountSettings)
    ]
    var body: some View {
        List {
            ForEach(entries.indices, id: \.self) { index in
                let entry = entries[index]
                if query.isEmpty || (entry.0 + " " + entry.1).localizedCaseInsensitiveContains(query.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    Button { onOpenRoute(entry.2) } label: {
                        VStack(alignment: .leading, spacing: 6) { Text(entry.0).font(.headline); Text(entry.1).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }.navigationTitle("搜索设置").searchable(text: $query, prompt: "搜索设置名称或关键词")
    }
}
