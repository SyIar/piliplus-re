# PiliPlus Swift

面向 iOS 的 Swift / SwiftUI 原生迁移项目，播放器使用 **AVPlayer**，界面按 **ChunUI** 的语义配色、字号层级与组件规范逐步重构，并采用 iOS **Liquid Glass**。

仓库：<https://github.com/SyIar/piliplus-re> · GPL-3.0-only。

**当前为 0.1 开发版本，尚未实现 PiliPlus 全部功能，也尚未完成真机验收。** 功能状态见 [迁移对照](docs/FEATURE_PARITY.md) 和 [原版逐项清单](docs/PILIPLUS_FEATURE_INVENTORY.md)。构建通过只证明编译和自动化测试通过，不代表全部业务可用。

## 原生实现

- 基于 GPL-3.0 的 [cilicili](https://github.com/Rone89/cilicili) 原生代码继续开发，保留其账号、推荐、搜索、动态、评论、消息、直播与弹幕实现。
- AVPlayer HLS Bridge 适配 B 站分离音视频流；没有 Flutter 或 mpv 运行时。
- 新增视频模式多 P、番剧、收藏夹和稍后再看顺序播放、循环，以及相关视频连播；收藏夹按需分页，听视频模式保留已有队列。
- 全局定时停止：按实际截止时间计时，支持播完当前再停；到点停止优先于连播，并持久化状态。
- 空降助手沿用 SponsorBlock 服务，合并重叠区间，减少连续 seek。
- 稍后再看支持加入、移除，以及清理已看完和失效条目；写操作需登录对应账号。
- 新增离线下载队列、多 P 与画质选择、暂停续传、后台传输、音视频合并、离线播放与弹幕、批量管理；首轮设备与模拟器测试包编译通过，等待功能验收。
- 新增字幕时间轴与文件导入导出、互动视频分支、文本笔记及 WebDAV 设置备份；这批增量等待云端编译，细项差异以迁移清单为准。
- ChunUI 主题、13/17/24 字号层级、Pika 图标、播放设置与原生玻璃按钮已接入，其他页面仍在迁移。

DLNA 的后台/队列/设备适配、笔记富文本、高级字幕、图像导出及其他细项仍有明确缺口；详情以迁移清单为准。此前反馈的退出视频瞬态爆音，必须在目标 iPhone 和 iOS 上复测，不能仅凭更换播放器宣称修复。

## 开发与构建

- iOS 26.1+，macOS + Xcode 26.5 或更新版本。
- Swift 6 工具链；主应用使用 Swift 5 语言模式、默认 MainActor 隔离和 Approachable Concurrency。
- Xcode 项目与 scheme 暂保留内部名 `bili`，应用显示名为 `PiliPlus Swift`，Bundle ID 为 `io.github.syiar.PiliPlusSwift`。
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

下载入口：[Releases](https://github.com/SyIar/piliplus-re/releases)。基础设备 IPA 已在 Actions 构建成功，完整测试通过后才会生成 Release。

IPA **未签名**，需要自行签名后安装。流水线不需要个人证书，也不会发布到 App Store 或 TestFlight。只有全部构建与测试成功才会执行发布任务。

首次迁移期间暂停 Dependabot 版本更新 PR，并跳过机器人 PR 的昂贵 macOS 任务，避免旧模拟器任务占满构建资源；可以手动运行这些分支的验证。主分支和版本标签始终执行完整测试，其他分支的手动运行不会发布 Release。

## 播放策略与界面

`Packages/PiliPlaybackCore` 包含独立于播放器和 UI 的连播、睡眠计时与空降区间策略，可在 Linux/macOS 上测试。原生应用在播放结束、后台恢复和引擎状态回调中使用这些策略，处理定时停止与下一条加载之间的竞态。

`PiliChunUIBridge` 集中配置颜色与中文文案；`PiliPlaybackToolsView` 使用 ChunUI 的展示层。玻璃效果用于播放控件与导航，内容区域保留可读的背景。

## 来源和许可证

本项目是独立衍生版本，不代表 PiliPlus、cilicili、ChunUI 或哔哩哔哩官方。完整来源、固定 revision 和许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 与 [LICENSE](LICENSE)。修改与分发时保留上游版权，并提供对应源代码和构建说明。
