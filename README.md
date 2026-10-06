# PiliPlus Swift

面向 iOS 的 Swift / SwiftUI 原生迁移项目，播放器使用 **AVPlayer**，界面按 **ChunUI** 的语义配色、字号层级与组件规范逐步重构，并采用 iOS **Liquid Glass**。

仓库：<https://github.com/SyIar/piliplus-re> · GPL-3.0-only。

应用显示名称为「哔哩哔哩」，图标采用用户指定的白底黑色小电视高清版本，见 [图标来源与生成记录](docs/APP_ICON.md)。这是本仓库的第三方原生客户端。

**当前为 0.1 开发版本，已接入下述业务，仍需签名后的真机与线上账号验收。** 对照 PiliPlus v2.1.6，按用户要求排除一起看、人像防挡和 Chromecast；iOS 实现与平台差异见 [交付记录](docs/PILIPLUS_FULL_ALIGNMENT.md) 和 [原版逐项清单](docs/PILIPLUS_FEATURE_INVENTORY.md)。构建通过只证明编译和自动化测试通过，不代表全部线上业务已验收。

2026-10-06：保留参考图风格的首页、浮动底栏和横屏液态玻璃控件，默认强调色为 `#3264F0`。本轮继续补齐动态发布、社区与收藏、空间内容、播放工具和账号设置；[Swift 性能核查](docs/SWIFT_PERFORMANCE_AUDIT.md) 记录官方依据、已处理热点及需要真机采样的项目。当前提交的编译与测试结果以 Actions 为准。

## 原生实现

- 基于 GPL-3.0 的 [cilicili](https://github.com/Rone89/cilicili) 原生代码继续开发，保留其账号、推荐、搜索、动态、评论、消息、直播与弹幕实现。
- AVPlayer HLS Bridge 适配 B 站分离音视频流；没有 Flutter 或 mpv 运行时。
- 新增视频模式多 P、番剧、收藏夹和稍后再看顺序播放、循环，以及相关视频连播；收藏夹按需分页，听视频模式保留已有队列。
- 全局定时停止：按实际截止时间计时，支持播完当前再停；到点停止优先于连播，并持久化状态。
- 空降助手沿用 SponsorBlock 服务，合并重叠区间，减少连续 seek。
- 稍后再看支持加入、移除，以及清理已看完和失效条目；写操作需登录对应账号。
- 离线下载队列、多 P 与画质选择、暂停续传、后台传输、音视频合并、离线播放与弹幕、整合集与批量管理；DLNA 支持双轨/离线转发、分页连播和定时停止。
- 双语字幕、时间轴与文件导入导出、AI 翻译音轨、高级/会员弹幕、重复弹幕合并；复杂互动视频支持条件变量、画面热点与回溯。
- 树状评论、完整内容长图、带图动态/投票/预约、消息设置与内容卡片；原生图文、课程、追番与收藏管理、AU 音频、BGM、小站、赛事及更多空间内容。
- 章节/高能曲线、GIF/Live Photo、MetalFX SDR 超分、社区空降分类和投票、笔记及 WebDAV 设置备份；完整能力和资源限制见逐项清单。
- ChunUI 主题、13/17/24 字号层级、Pika 图标与原生玻璃按钮；设置搜索、内容过滤、评论归档、账号记录/隐私和高刷新率偏好。
- 视频弹幕云端屏蔽与本人撤回、推荐反馈/视频点踩、标题与分区正则及关注豁免、AI 总结与大纲跳转；按账号快速收藏、常用直播分区和独立直播画质/CDN 偏好。剩余差异见逐项清单开头的二次盘点。

真实后台、锁屏/PiP、照片库、HDR/GPU 功耗和电视兼容性仍待真机验收。富文本笔记、举报表单、漫画阅读与商品详情复用官方网页；DLNA 转发有前台、网络与接收端要求；Android/mpv 专属能力不等同于 iOS。详见交付记录。此前反馈的退出视频瞬态爆音，必须在目标 iPhone 和 iOS 上复测，不能仅凭更换播放器宣称修复。

## 开发与构建

- iOS 26.1+，macOS + Xcode 26.5 或更新版本。
- Swift 6 工具链及语言模式（应用、单元测试、UI 测试、核心包）；主应用保留默认 MainActor 隔离和 Approachable Concurrency，启用完整并发检查。
- Xcode 项目与 scheme 暂保留内部名 `bili`，应用显示名为 `哔哩哔哩`；Debug Bundle ID 为 `io.github.syiar.PiliPlusSwift`，Release 为 `cc.bili`。
- ChunUI 固定到源码 revision；Swift Package Manager 在首次构建时解析依赖。

```bash
git clone https://github.com/SyIar/piliplus-re.git
cd piliplus-re
swift test --package-path Packages/PiliPlaybackCore
python3 Scripts/validate-project.py
bash Scripts/test-ios.sh
bash Scripts/build-ipa.sh
```

也可用 Xcode 打开 `bili.xcodeproj` 并运行 `bili` scheme。真机调试在本地选择自己的 Team；签名配置不提交到仓库。

## GitHub Actions 与下载

工作流：[Build, test and publish IPA](.github/workflows/build-release.yml)。

1. PR、`main` 推送、`v*` 标签或手动运行触发 macOS 构建。
2. 执行播放策略测试、仓库校验；单独编译 iOS 测试包，再在预先启动的单台模拟器上运行测试与截图。
3. 并行编译设备 Release 包并生成 `PiliPlusSwift-unsigned.ipa`，上传 Actions artifact。
4. `main` 和标签的成功构建自动创建预发布，附 IPA、SHA-256、对应源代码和许可说明。PR 只构建，不发布。

下载入口：[Releases](https://github.com/SyIar/piliplus-re/releases)。每份构建附 `SOURCE_COMMIT.txt`，可核对对应提交；完整验证记录见 [交付记录](docs/PILIPLUS_FULL_ALIGNMENT.md)。

IPA **未签名**，需要自行签名后安装。流水线不需要个人证书，也不会发布到 App Store 或 TestFlight。只有全部构建与测试成功才会执行发布任务。

首次迁移期间暂停 Dependabot 版本更新 PR，并跳过机器人 PR 的昂贵 macOS 任务，避免旧模拟器任务占满构建资源；可以手动运行这些分支的验证。主分支和版本标签始终执行完整测试，其他分支的手动运行不会发布 Release。

## 播放策略与界面

`Packages/PiliPlaybackCore` 包含独立于播放器和 UI 的连播、睡眠计时与空降区间策略，可在 Linux/macOS 上测试。原生应用在播放结束、后台恢复和引擎状态回调中使用这些策略，处理定时停止与下一条加载之间的竞态。

`PiliChunUIBridge` 集中配置颜色与中文文案；`PiliPlaybackToolsView` 使用 ChunUI 的展示层。玻璃效果用于播放控件与导航，内容区域保留可读的背景。

## 来源和许可证

本项目是独立衍生版本，不代表 PiliPlus、cilicili、ChunUI 或哔哩哔哩官方。完整来源、固定 revision 和许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 与 [LICENSE](LICENSE)。修改与分发时保留上游版权，并提供对应源代码和构建说明。
