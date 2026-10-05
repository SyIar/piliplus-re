# 来源与许可

PiliPlus Swift 是独立的 Swift 原生迁移项目，不是 PiliPlus、cilicili 或哔哩哔哩的官方发行版。

## cilicili

- 来源：<https://github.com/Rone89/cilicili>
- 基线：`c61b0d33966c5d8e87ea20527b8ba48c702c10c1`
- 许可：GPL-3.0-only，见根目录 `LICENSE`。
- 本仓库基于该项目的 SwiftUI 应用、B 站接口、账号存储、弹幕和 AVPlayer HLS Bridge 实现修改，保留原有代码与提交来源。原始 README 见 `docs/upstream/CILICILI_README.md`。
- 新增的播放策略、全局定时停止、ChunUI 集成和流水线同样按 GPL-3.0-only 提供。

## PiliPlus

- 来源：<https://github.com/bggRGjQaUbCoE/PiliPlus>
- 用户安装版本基线：`a30fcc31043e10cd38c198f47ddd7b23fd6e6163`（2.1.5）。
- 本次功能盘点同时参考当前源码 `e5ede1a8f7227d35dd24454c9c206dcb175e754a`。
- 许可：GPL-3.0，许可文本见 `Licenses/PiliPlus-LICENSE`。
- 用途：功能迁移对照与接口行为参考；不包含 Flutter 或 mpv 运行时。旧版应用图标取自上述 2.1.5 基线的 iOS 资源，现已替换；新图标来源与处理记录见 `docs/APP_ICON.md`。

## ChunUI

- 来源：<https://github.com/liseami/ChunUI>
- 锁定源码：`b240cbbdb9c6d7afc9f02d9ce4ddff5a25ce73bb`。
- Copyright (c) 2026 liseami，MIT，见 `Licenses/ChunUI-LICENSE`。
- 通过 Swift Package Manager 引入；使用语义颜色、13/17/24 字号层级、PikaIcon、CCNeoButton、原生 sheet 和 toast。
- ChunUI 的传递依赖 Pow 保留其 MIT 许可，见 `Licenses/Pow-LICENSE`；具体版本以构建输出的 SwiftPM 锁文件为准。
- 应用内“关于 → 查看开源许可证”提供随包许可证，离线可读。

## Apple 系统框架

AVFoundation、AVKit、SwiftUI、UIKit、WebKit、Network 和 Security 由 iOS SDK 提供，不在本仓库重新分发。

## 分发

每个 IPA Release 应同时提供对应 Git 提交的完整源代码归档、GPL 许可、此来源说明、SwiftPM 依赖锁定信息和构建说明。开源许可不表示上游维护者认可本分支，也不授予其商标背书。
