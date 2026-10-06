# 默认蓝色、迁移缺口与上游开放事项评估

> 后续进度：近期八项增强已合入 main 并发布，见 [近期实现记录](NEAR_TERM_IMPLEMENTATION.md)。树状评论、重复弹幕合并和复杂互动视频见 [2026-10-06 增量](COMMENT_DANMAKU_INTERACTIVE.md)；用户已排除 VideoTogether/Chromecast，人像防挡暂不纳入。本文件保留 2026-10-05 的审计快照，其中“待迁移”不覆盖后续实现状态。

评估日期：2026-10-05。原生代码基线为 [`4cabbcc9`](https://github.com/SyIar/piliplus-re/commit/4cabbcc9e97b5dde79c4013932b3a5db55623971)，上游 main 为 [`7a4f442f`](https://github.com/bggRGjQaUbCoE/PiliPlus/commit/7a4f442f450ff0698d0fbe5cecb9666cd1c12e3f)。本次产品改动是主题色；下文的候选功能是评估结果，并未在本次全部实现。

通过 GitHub REST API 分页获取当时全部 **32 个 open PR、268 个 open issue**；issue 统计排除了 PR。读取事项正文、32 个 PR 的变更文件列表，并重点复核候选补丁、相关讨论和本仓库实现。此文是迁移/排期初筛，不是对所有 PR 的完整安全审计或真机验收。关闭但未合并的 PR 不属于本次“当前未合并 PR”的统计口径。

## 本次主题改动

- 原默认色为绿色 `#56B47B`，改为接近用户截图按钮主体的蓝色 **`#3264F0`**。截图有渐变和玻璃高光，不能用单一十六进制颜色精确代表整张按钮；玻璃材质继续由现有原生组件提供。
- 新安装直接使用蓝色；旧默认绿色通过 v4 标记迁移一次。旧存储无法区分“默认绿色”和“用户手动选择了同一绿色”，因此该精确值都会迁移一次；其他自定义颜色保留，迁移后重新选择绿色不会再被覆盖。
- 绿色仍在调色板中。修改 `AppThemeTintColor`、`LibraryStore`，测试覆盖默认值、旧色迁移、第二次启动和自定义颜色保留。
- CI 继续执行核心测试、iOS 单元测试、液态玻璃 UI 测试、Release 编译、明暗/横屏预览及未签名 IPA 发布。运行结果以对应提交的 Actions/Release 为准，不把上一次成功当成本次通过。

## 上游 main 已有，原生尚未完整迁移

这些是与上游当前 main 的差异；后面尚未合并 PR 的新能力不混入这一列表。更早逐项记录见 [功能对照](FEATURE_PARITY.md) 和 [源码核对](UPSTREAM_AUDIT_2026-10-05.md)。

| 模块 | 仍缺的功能 | 原生已有基础 / 实现位置 |
| --- | --- | --- |
| 动态创作与管理 | 发布、编辑、删除、置顶、转发，投票/话题选择 | 已有动态流、详情、评论、点赞；`BiliAPIClient+Dynamic` / `Features/Dynamic` |
| 消息 | 全局消息设置、折叠会话，以及视频/番剧/动态/专栏/直播内容卡片发送 | 已有私信文字/图片、撤回、会话删除/置顶/免打扰及聊天推送设置；`AccountMessageService` |
| 评论 | 楼中楼热度/时间切换；翻译等路径仍需补齐/核对 | 已有列表、楼中楼、对话、评论锚点、点赞/点踩、删除/置顶/举报；评论与弹幕的举报是不同功能 |
| 弹幕 | 点击悬停、复制、点赞/举报，高级弹幕/特殊交互 | 当前普通弹幕显示/发送与设置不等于高级模式；`DanmakuOverlayView` |
| 课堂/追番/订阅 | PUGV 课堂专用鉴权/播放与已购入口、追番状态管理、合集订阅/退订及完整列表 | 已有 PGC/合集播放、队列；不能把 PGC 当作 PUGV |
| 图文/专栏 | 专栏原生正文、独立图文列表、文章互动 | 已有动态中的图文展示及链接路由，网页打开不能算原生正文迁移完成 |
| 登录与搜索 | 手动粘贴 Cookie 登录、用户动态关键词搜索、完整 @ 用户选择 | 已有二维码/短信/Web 登录、多账号、空间动态分页 |
| 离线 | 上游本次 main 的 UGC 合集归组与对应整合集离线入口 | 已有多 P 下载、后台队列、续传、字幕/弹幕保存、合并视频和系统导出；`PiliOfflineStore` |
| 投屏 | 投屏自动切集/队列、后台控制与更多媒体/网络类型兼容 | 已有 DLNA 发现、手动设备、控制、双轨 HLS/离线转发；IPv6-only、FLV 等仍有边界，需电视验收 |
| 字幕 | 未登录 gRPC 兜底、完整静音自动选轨策略、PiP 字幕 | 已有在线/离线字幕、导入导出、样式、列表按秒跳转；`PiliSubtitleController/Views` |
| 笔记 | 完整富文本、图片、截图和可跳转时间标签 | 已有原生文本编辑/列表/发布/删除与失败草稿；富文本暂只读以免丢失内容 |
| 媒体工具 | 截图、GIF、Live Photo 导出，超分、AI 原声翻译 | 当前普通视频导出不能替代这些处理能力；AVPlayer 无法直接复用 mpv 滤镜 |
| 界面统一 | 将剩余表单、消息、直播、离线等页面逐页统一到参考图风格 | 首页、底栏、详情工具和横屏播放器已经重构；不把全局 tint 改色当作全 App UI 完成 |

互动视频要单独说明：当前原生与上游 main 都有基础分支流程；本仓库还支持路径回看/保存。隐藏变量、条件表达式、倒计时/默认选择、热点、自动节点、禁止回溯与失败回滚主要是 **open PR #3172 的增强**，不能全部叫作“漏迁移了上游已完成的功能”。同理，仅音频下载、人像防挡、一起看、树状评论等也应列为待评估新能力。

折叠评论（#2391）、客服消息（#3173）、离线章节（#3069）和动态草稿改进（#2272）来自尚开放的需求，也单独列在 issue 候选中，不作为上游 main 已完成的迁移基线。

## 推荐实施顺序与验收条件

P0 指可靠性优先，并不表示已确认发生了上游同一个故障。P1 是可独立交付的常用增强，P2 是较大或可选模块；工作量表示相对范围，不是工期承诺。

| 顺序 | 建议工作 | 依据与当前判断 | 完成交付的最低验收 |
| --- | --- | --- | --- |
| 1 · P0 | 下载完成校验 | [PR #2799](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/2799)。`PiliOfflineSessionDelegate.didFinishDownloadingTo` 目前只检查 2xx 和非零文件。URLSession 管理 resumeData，**没有证据表明存在 Dart 手动 append 的同一 bug**，但长度、媒体类型和最终资产可播放性值得补强 | 中断/恢复、忽略 Range、错误 206/416、200 返回 HTML、截断、未知长度；校验失败不标记完成、不删除可恢复状态 |
| 2 · P0 | 直播弹幕资源限制 | [PR #2801](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/2801)。原生 `LiveDanmakuService` 已是 nonisolated，不能说解压仍在主线程；但 `inflate` 持续追加输出，压缩嵌套递归缺少明确总量/深度预算 | 限制帧大小、累计解压量、包数、嵌套深度；坏包、压缩炸弹样本、断线重连及顺序测试；不阻塞 UI |
| 3 · P0/P1 | 原生播放生命周期回归 | [#3186](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/3186)、[#3165](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/3165)、[#3057](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/3057)、[#2990](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2990)、[#2694](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2694)。都是有价值的验收触发条件，尚未在原生仓库复现 | 来电/FaceTime、耳机拔出、蓝牙切换、前后台/锁屏、Wi-Fi→蜂窝、切 P/清晰度；持续保留进度及正确播放意图，用户主动暂停不应被自动恢复 |
| 4 · P1 | 完整离线体验 | [PR #3166](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3166)、[PR #2960](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/2960)，[#3079](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/3079)、[#3069](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/3069)、[#2726](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2726)。现有下载要求视频轨，列表批量管理尚未接入批量缓存 | 收藏/稍后再看跨页选择、按 CID 去重、失效/无权限条目说明、合集归组；仅音频任务无视频请求，可暂停续传/后台/离线播放/导出 |
| 5 · P1 | 锁定方向、无障碍与字幕 | [#2424](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2424)、[#2524](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2524)、[#2399](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2399)、[#3150](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/3150)、[#2568](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2568)。当前玻璃锁定只限制触摸；字幕目前固定白色/单选轨 | 防误触与锁定当前方向分开，解锁恢复正常旋转；VoiceOver、超大字体和减少透明度；字幕前景色/双语时间轴对齐及偏移测试 |
| 6 · P1 | 评论读取账号独立选择 | [PR #3042](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3042)。`BiliAccountPurpose` 尚无 commentRead，现有互动账号不能代替读取用途 | 评论列表/楼中楼/对话/翻译统一读账号；匿名不带登录 Cookie；写入仍绑定互动账号，切换账号取消旧请求并隔离缓存 |
| 7 · P1 | 测速反馈与音质策略 | [PR #3055](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3055)、[PR #2657](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/2657)。原生已有测速/自动选择；`bestAudioStream` 目前 AAC 优先，自动不等于优先最高音质 | 测速进度/停流归零/取消/全失败保留设置；可选优先无损或 Dolby，按设备能力回退并保留兼容默认；切换保留进度 |
| 8 · P1，分阶段 | 复杂互动视频 | [PR #3172](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3172)。原生只解析首组选项及 CID，历史只有 edgeID/CID/title；尚无变量快照与条件状态机 | 先纯 Swift 状态机/表达式与图样本，再接热点/倒计时；无界循环防护；选择失败不能提交历史；恢复/回溯同步变量；账号/图版本隔离 |
| 9 · P1 | 原版动态/消息主流程 | 上述迁移缺口；[#2272](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2272)、[#3173](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/3173) 可一起纳入设计 | 先动态文本/图片与草稿、服务端明确返回再更新列表；随后私信卡片与全局设置；账号权限/风控失败需可恢复 |

## 全部 32 个 open PR 的判断

以下“借鉴”指业务规则、边界和测试设计，不能直接 cherry-pick Dart/Flutter 补丁到 Swift 项目。表中“已有”仅表示源码有基础实现；未作真机验证的兼容性不宣称已解决。

| PR | 主题 | 在本仓库的判断与工作范围 |
| --- | --- | --- |
| [#3183](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3183) | Windows 启动/退出 | 不直接移植。WinRT、Windows 窗口销毁路径不适用 iOS；可借鉴缓存失败的错误提示。 |
| [#3172](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3172) | 完整互动视频 | P1，较大，分阶段实现。变量/条件/自动节点/默认选择/回滚/热点都值得补；讨论已把 Windows 部分拆到 #3183，仍不宜整包照搬。 |
| [#3166](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3166) | 收藏/稍后再看批量缓存 | P1，中。复用现有列表批选与下载队列，重点是完整分页、权限/失效筛选、CID 去重和可取消入队。 |
| [#3161](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3161) | VideoTogether 一起看 | P2，大。可做可选模块，但房间/时钟同步、控制权、断线重连与外部服务维护需要单独设计。 |
| [#3145](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3145) | CDN、直播、应用内小窗/队列 | 拆分评估。原生已有 CDN 探测/避让、直播换线、系统 PiP/播放队列；应用内小窗不同于 PiP。61 个变更文件的广泛改动不宜一次引入。 |
| [#3144](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3144) | 换 CDN 保留进度 | P1，回归优先。已有 `currentPlaybackResumeTime` 与切流交接；仍应沿“设置/测速→重载”逐入口验证真实零进度、旧进度回退、暂停和倍速。尚未确认同一缺陷。 |
| [#3130](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3130) | 英文/繁体本地化 | P2，大。应使用原生 String Catalog 和格式化复数/日期，不能移植 Flutter 生成文件；423 个变更文件提示维护范围较大。 |
| [#3100](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3100) | 自定义播放器快捷键 | P2，中。可做 iPad 硬件键盘的 UIKeyCommand/焦点方案；输入文字时不拦截空格、方向键。 |
| [#3091](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3091) | 一键测速/选最快 CDN | 已有基础。`PlaybackNetworkDiagnosticsSheetActions` 已探测真实播放 URL 并应用推荐，失败保留；可增加吞吐量可比性。不能用无播放 URL 的 Host 弱探测结果代替真实速度。 |
| [#3088](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3088) | 随显示区域调整解码输出 | 不直接移植。修改的是 media_kit 原生纹理尺寸；AVPlayerLayer 没有同一控制路径。先量测原生 GPU/解码/缩放再决定优化，不能保证同等省电。 |
| [#3081](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3081) | AI 内容识别/折叠 | P2，大，可选。先做可解释本地过滤；如接第三方模型，需用户配置、Keychain、缓存/取消/费用边界及明确发送哪些内容。 |
| [#3077](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3077) | 弹幕避开挖孔 | P1，中，借鉴需求。补丁是 Android 折叠屏 MethodChannel；原生用实际视频区域与 safeAreaInsets，横竖屏/缩放时重新计算。 |
| [#3060](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3060) | Windows ARM64 Release | 不适用当前 iOS 产品。 |
| [#3055](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3055) | 实时测速进度 | P1，中。现有原生主要在测完更新结果；可补当前节点、字节量、实时速度、停流与取消。PR 评论中的测试通过是作者报告，不是本仓库验证。 |
| [#3042](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3042) | 评论获取账号 | P1，中。新增读取用途和匿名选项；注意读写账号分离及发送后可见性检查仍使用发送账号。 |
| [#3035](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3035) | 多线程/多 CDN 加速 | P2，大，实验功能。原生已有 HLS Bridge/预取；并发与 Range/续传/缓存一致性、电量/蜂窝预算需先设计，不能作为海外卡顿的万能修复。 |
| [#3031](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3031) | 平板横屏安全区白条 | 不直接移植 Flutter padding。原生已做全幅播放器背景；将 iPad 分屏/旋转/刘海纳入布局回归。 |
| [#3007](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/3007) | 全关注 UP 动态红点 | P1，中。可补本地已读水位、全部关注分页与账号隔离；相关 #2669，不能只显示最常访问列表就算完成。 |
| [#2995](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/2995) | 全屏方向残留/默认方向 | P1，回归与原生协调。复用 AppOrientationLock/旋转协调器；当前防误触锁未锁方向，#2424/#2524 可独立解决。 |
| [#2977](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/2977) | Android 手柄 Back/Home | 不直接移植。iPad 手柄需 GameController，并尊重系统 Home 行为；非当前优先项。 |
| [#2960](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/2960) | 仅音频缓存/播放 | P1，中到大。现有入队要求 videoURL；要修改任务类型、完成条件、索引、导出与离线播放器，不能只隐藏视频画面。 |
| [#2948](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/2948) | 蒙版人像防挡 | P2，大。需要解析真实 dm_mask/WebMask、同步与坐标映射/GPU 合成；#2749 讨论提示文档可能不准确，先验证样本。 |
| [#2927](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/2927) | 树状评论 | P2，中到大。原生已有楼中楼；新增父子树、任意层折叠、分页续载与已删父节点占位，避免超深布局。 |
| [#2866](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/2866) | Dart 预构建/FVM 隔离 | 不适用 Xcode/Swift 工程。 |
| [#2847](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/2847) | Chromecast | P2，大。DLNA 已有但不是 Cast；需原生 Cast SDK/发现/会话/投送和电视实测，媒体 URL 与请求头不应泄露账号凭据。 |
| [#2801](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/2801) | 直播解压移出 UI | P0，中。线程模型已不同，重点采纳帧/解压总量/包数/深度限制与失败恢复，不重复实现 Dart isolate。 |
| [#2799](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/2799) | 断点续传完整性 | P0，中。把响应与最终文件校验设计用于 URLSession 原生下载；不复制 Dart 文件追加策略。 |
| [#2737](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/2737) | Linux MPRIS | 不适用。原生已有 MPRemoteCommandCenter，应验收锁屏/耳机/队列命令。 |
| [#2657](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/2657) | 自动最佳音质 | P1，中。当前自动流选择偏 AAC 兼容性；可补独立可选策略及 Wi-Fi/蜂窝偏好，失败退回可用流。 |
| [#2608](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/2608) | iOS 暂停爆音 | 不直接加其 mpv 125ms 渐弱。原生没有同一调用链；把暂停/返回/音频中断作为真机回归，确认原因后修复。 |
| [#2476](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/2476) | 弹幕合并 | P1，中。当前原生 segment merge 主要做 ID 合并，不能当作同文计数。可补有界时间窗口、先过滤、按用户去重；注意窗口边界与无 midHash 的策略。 |
| [#2468](https://github.com/bggRGjQaUbCoE/PiliPlus/pull/2468) | pre-build task | 不适用 Flutter 构建脚本；保留当前 Xcode Actions 门禁。 |

## 268 个 open issue 的完整初筛

完整可筛选列表：**[UPSTREAM_ISSUE_TRIAGE_2026-10-05.csv](UPSTREAM_ISSUE_TRIAGE_2026-10-05.csv)**。每行保留编号、标题、链接、当时状态/更新时间、判断、优先级与原生范围。复合 issue 按主结论计一次，不能把计数直接等同于可一次交付的功能数量。

| 判断 | 数量 | 含义 |
| --- | ---: | --- |
| 可实现的原生增强 | 65 | API、数据状态、下载、字幕、音频策略等，可按独立交付排期 |
| 可实现的界面与交互增强 | 48 | 快捷入口、精确进度、手势、iPad 布局等；先核验已有入口 |
| 已有基础，核对剩余差异 | 18 | 不应整项重复开发，细节和真实设备兼容性仍需验证 |
| 原生复现与回归候选 | 35 | 有用的故障场景，尚未证明本仓库存在相同缺陷 |
| 较大功能或外部依赖 | 24 | 一起看、蒙版、第三方服务、投屏兼容等专项 |
| 复合需求需拆分 | 5 | 一个 issue 包含多个独立子项，不能一项修复就标全部解决 |
| 发布与分发增强 | 4 | 说明、版本命名/更新识别、AltStore 等 |
| 平台或后端不直接适用 | 65 | Android/桌面系统、Flutter/mpv 专用机制，不在当前原生产品直接移植 |
| 信息不足 | 4 | #3087、#2887、#2656、#2617 缺少可执行细节 |
| 合计 | **268** | 不含 PR |

### 已有能力需要避免重复建设

| 上游 issue | 本仓库现状与剩余部分 |
| --- | --- |
| [#2835](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2835) 字幕列表 | 已有列表及按秒跳转，上次交付修正了跳转单位；本次不重复算缺失。 |
| [#2588](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2588) 缓存字幕 | 已自动保存/离线读取；语言包含/排除、跳过 AI 等高级策略仍可补。 |
| [#3152](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/3152)、[#2748](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2748) 导出 | 已有音视频合并与完整视频分享导出；音频单独导出、命名和外置路径不是同一个完成项。 |
| [#2541](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2541) 备份密码 | WebDAV 密码放 Keychain，SettingsArchive 排除凭据，已有测试。 |
| [#2764](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2764)、[#2670](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2670) 媒体按键 | 已有系统播放/暂停和队列控制；真实耳机、后台仍需验收。 |
| [#2419](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2419) 互动回溯 | 基础路径回看已做；变量快照和禁止回溯必须与 #3172 状态机一起补。 |
| [#2880](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2880)、[#3040](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/3040) 下一集/听视频 | 已有跨 P/列表分页和共享队列，仍需按上游报告的边界复现。 |
| [#3019](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/3019)、[#2033](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2033) 评论跳转 | 已有路由/锚点；深层回复、分页与已删除节点仍要验证。 |
| [#2420](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2420) 直播换线 | 已有 LiveStreamMenu、手动/首帧慢备用；具体节点选择粒度还可完善。 |
| [#2663](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/2663) CDN 管理 | 已有自定义节点与测速；节点禁用、排序、优先级是增量。 |

## 证据与边界

- 本次直接改代码的是蓝色主题和升级迁移；候选清单不代表已合入对应功能。
- 重点源码：`Services/PiliOfflineSessionDelegate.swift`、`Services/PiliOfflineStore.swift`、`Services/LiveDanmakuService.swift`、`Features/Player/PiliInteractiveController.swift`、`Models/PiliInteractiveVideo.swift`、`Services/MultiAccountSessionModels.swift`、`Models/BiliModels.swift`、`Features/VideoDetail/PlaybackNetworkDiagnosticsSheetActions.swift`、`Features/VideoDetail/UIKitShell/VideoDetailShellSurfaceHost.swift`。
- 本次查看了候选 PR #3172/#3166/#3144/#3091/#3055/#3042/#2960/#2801/#2799/#2657/#2476 的 issue discussion，以及 #2941/#3186/#3057/#2424/#2694/#2588/#2749/#2568/#3079 的讨论。没有将作者自述测试、未下载的附件或第三方模型生成的结论作为本仓库验收证据。
- iOS AVPlayer 与上游 iOS mpv 也不是同一播放后端。不能因平台都叫 iOS 就应用 mpv 音频渐弱/解码参数补丁；也不能因后端不同就宣称永远不会出现音画不同步、耗电或后台问题。
- 服务端可见性、账号权限、限定直播、Chromecast/DLNA 电视与音频设备需要实际验收；不保证拿到 API 不返回的内容，不保证零延迟或所有设备兼容。
