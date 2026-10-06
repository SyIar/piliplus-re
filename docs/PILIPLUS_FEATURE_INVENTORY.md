# PiliPlus 原版功能逐项盘点

对照 PiliPlus v2.1.6 `4ed5968f37af8b4aa7e0f13178cb8d8c2f86defc`（2026-10-06）；原生开发基线 `4ba12a3`。本表替代旧的“待核验”基线表，按实际代码与入口描述当前状态。

用户明确排除：**一起看、人像防挡、Chromecast**。目标平台为 Swift iOS/iPadOS，Android/桌面的系统接口不会原样移植。

“已接入”表示有业务实现、入口和失败处理，不等于线上账号/电视/设备验收完成。当前完整 CI 结果与已知边界以 [交付记录](PILIPLUS_FULL_ALIGNMENT.md) 为准；不会将分组标题、重复条目或平台差异加总成“100%”。

| 序号 | 上游条目 | 原生实现与证据 |
| --- | --- | --- |
| 1 | Android | 平台范围：本仓库交付 iOS/iPadOS，不生成 Android/Windows/Linux 程序 |
| 2 | iOS | 已接入 iOS 26.1+/iPadOS 原生工程、横竖屏和自适应布局；签名与真机待验收；[RootTabView.swift](../bili/Sources/App/RootTabView.swift) |
| 3 | Pad | 已接入 iOS 26.1+/iPadOS 原生工程、横竖屏和自适应布局；签名与真机待验收；[RootTabView.swift](../bili/Sources/App/RootTabView.swift) |
| 4 | Windows | 平台范围：本仓库交付 iOS/iPadOS，不生成 Android/Windows/Linux 程序 |
| 5 | Linux | 平台范围：本仓库交付 iOS/iPadOS，不生成 Android/Windows/Linux 程序 |
| 6 | 用户界面 | 上游分组标题，不计为一项独立功能 |
| 7 | 其他 | 上游分组标题，不计为一项独立功能 |
| 8 | 编辑动态 | 已接入发布、转发、编辑、删除、置顶/取消置顶，失败草稿与身份校验；[PiliDynamicComposer.swift](../bili/Sources/Features/Dynamic/PiliDynamicComposer.swift)、[PiliDynamicManagement.swift](../bili/Sources/Features/Dynamic/PiliDynamicManagement.swift) |
| 9 | DLNA 投屏 | 已接入设备发现/手动添加、遥控、双轨 HLS/离线文件、分页队列、多 P/自动切集及定时停止；电视/组播签名/前后台边界见 DLNA 文档；[PiliDLNAController.swift](../bili/Sources/Services/PiliDLNAController.swift)、[PiliCastQueue.swift](../bili/Sources/Services/PiliCastQueue.swift) |
| 10 | 离线缓存/播放 | 已接入后台下载、续传/校验、双轨合并、音频/视频分组、批量下载与导出、离线播放器；后台调度待真机；[PiliOfflineStore.swift](../bili/Sources/Services/PiliOfflineStore.swift)、[PiliOfflinePlayerScreen.swift](../bili/Sources/Features/Player/PiliOfflinePlayerScreen.swift) |
| 11 | 移动端支持点击弹幕悬停，点赞、复制、举报 | 已接入弹幕点选、暂停查看、点赞/复制/举报；[PiliDanmakuActionsView.swift](../bili/Sources/Features/Player/PiliDanmakuActionsView.swift) |
| 12 | 播放音频 | 已接入听视频及独立 AU 音频、音质、列表、后台控制、定时停止；真实 AU 接口/后台待验收；[PiliAudioView.swift](../bili/Sources/Features/Player/PiliAudioView.swift)、[PiliAudio.swift](../bili/Sources/Services/PiliAudio.swift) |
| 13 | 跳过番剧片头/片尾 | 已接入番剧 clip 片头/片尾提示与可选自动跳过；[PiliPlayerMetadata.swift](../bili/Sources/Models/PiliPlayerMetadata.swift)、[PlayerStateViewModel.swift](../bili/Sources/Features/Player/PlayerStateViewModel.swift) |
| 14 | 安卓端 `loudnorm` 适配 | 平台差异：不移植 Android/mpv loudnorm 滤镜；AVPlayer 音轨能力与超分单独处理 |
| 15 | Win/Mac 支持极验、短信登录 | 平台差异：iOS 保留短信/二维码/Web 登录及极验流程，不生成桌面版本；[SMSLoginView.swift](../bili/Sources/Features/Mine/SMSLoginView.swift) |
| 16 | 视频截取动图 | 已接入片段 GIF 导出，限制时长、帧数与总像素，支持取消；[PiliMediaCapture.swift](../bili/Sources/Services/PiliMediaCapture.swift) |
| 17 | AI 原声翻译 | 已接入平台返回的 AI 原声翻译音轨，语言独立选择/缓存；不会为无权限内容生成音轨；[BiliAPIClient+PiliAudioLanguage.swift](../bili/Sources/Services/BiliAPIClient+PiliAudioLanguage.swift) |
| 18 | SuperChat | 已接入 SuperChat 卡片、展示策略、到期清理与历史；UI 自动化覆盖；[PiliSuperChatStore.swift](../bili/Sources/Features/Live/PiliSuperChatStore.swift)、[PiliLiveChatViews.swift](../bili/Sources/Features/Live/PiliLiveChatViews.swift) |
| 19 | 播放课堂视频 | 已接入 PUGV 课程列表/播放/分集/收藏、课程独立评论及历史类型；购买/访问权限由服务端决定；[BiliAPIClient+PiliCourses.swift](../bili/Sources/Services/BiliAPIClient+PiliCourses.swift) |
| 20 | 发起投票 | 已接入文字/图片投票、创建/修改、截止时间与校验；[PiliVoteCreator.swift](../bili/Sources/Features/Dynamic/PiliVoteCreator.swift) |
| 21 | 发布动态/评论支持`富文本编辑`/`表情显示`/`@用户` | 已接入动态/评论富文本、表情、图片、@ 用户及账号绑定提交；[PiliDynamicComposer.swift](../bili/Sources/Features/Dynamic/PiliDynamicComposer.swift)、[BiliAPIClient+Comments.swift](../bili/Sources/Services/BiliAPIClient+Comments.swift) |
| 22 | 修改消息设置 | 已接入 gRPC 全局及嵌套消息设置、未知 protobuf 字段保留；需 App 凭据；[PiliMessageSettingsView.swift](../bili/Sources/Features/Mine/PiliMessageSettingsView.swift) |
| 23 | 修改聊天设置 | 已接入会话设置、免打扰与服务端允许的内容推送选项；[PiliChatSettingsView.swift](../bili/Sources/Features/Mine/PiliChatSettingsView.swift) |
| 24 | 展示折叠消息 | 已接入折叠会话分页和私聊入口；[PiliFoldedMessagesView.swift](../bili/Sources/Features/Mine/PiliFoldedMessagesView.swift) |
| 25 | 查看用户图文 | 已接入用户图文、专栏/新图文正文、图片/公式/Live Photo、评论与互动；旧 HTML 使用禁用脚本的排版容器；[PiliArticleView.swift](../bili/Sources/Features/Dynamic/PiliArticleView.swift)、[PiliUserArticlesView.swift](../bili/Sources/Features/Uploader/PiliUserArticlesView.swift) |
| 26 | 动态话题 | 已接入话题搜索/选择、详情、排序、分页、折叠内容、参与讨论；[PiliSocialContentViews.swift](../bili/Sources/Features/Dynamic/PiliSocialContentViews.swift) |
| 27 | 直播分区 | 已接入直播分区、推荐与关注直播、分区榜单及房间导航；[PiliLiveExploreView.swift](../bili/Sources/Features/Live/PiliLiveExploreView.swift)、[LiveFeedView.swift](../bili/Sources/Features/Live/LiveFeedView.swift) |
| 28 | 分享`视频`/`番剧`/`动态`/`专栏`/`直播`至消息 | 已接入五类内容的私信卡片与收件人选择；与系统分享分开；[BiliAPIClient+PiliShare.swift](../bili/Sources/Services/BiliAPIClient+PiliShare.swift)、[PiliShareMenu.swift](../bili/Sources/Features/Mine/PiliShareMenu.swift) |
| 29 | 创建/修改/删除关注分组 | 已接入分组新建/改名/删除/排序、多个分组归属及特别关注；[PiliFollowGroupsView.swift](../bili/Sources/Features/Mine/PiliFollowGroupsView.swift) |
| 30 | 移除粉丝 | 已接入粉丝/关注/黑名单分页、搜索、关注/取关/移除粉丝及确认操作；[PiliRelationsView.swift](../bili/Sources/Features/Mine/PiliRelationsView.swift)、[BiliAPIClient+PiliRelations.swift](../bili/Sources/Services/BiliAPIClient+PiliRelations.swift) |
| 31 | 直播弹幕发送表情 | 已接入直播表情面板、文本/表情发送及回复元数据；[PiliLiveInteractionViews.swift](../bili/Sources/Features/Live/PiliLiveInteractionViews.swift) |
| 32 | 收藏夹排序 | 已接入收藏夹编辑/封面/排序、内容搜索/排序/多选/复制/移动/移除、清理确认；[PiliFavoriteFoldersView.swift](../bili/Sources/Features/Mine/PiliFavoriteFoldersView.swift)、[PiliFavoriteItemsView.swift](../bili/Sources/Features/Mine/PiliFavoriteItemsView.swift) |
| 33 | 稍后再看 ~~`未看`~~ / `未看完` / ~~`已看完`~~ 分类 | 已接入全部/未看完、搜索、添加时间正反序、多选管理与分页连播；[PiliWatchLaterToolsView.swift](../bili/Sources/Features/Mine/PiliWatchLaterToolsView.swift)、[BiliAPIClient+PiliWatchLater.swift](../bili/Sources/Services/BiliAPIClient+PiliWatchLater.swift) |
| 34 | WebDAV 备份/恢复设置 | 已接入本地及 WebDAV 设置备份/恢复/撤销；原生设置格式，密码保存在 Keychain；[PiliBackupSettingsView.swift](../bili/Sources/Features/Mine/PiliBackupSettingsView.swift) |
| 35 | 保存评论/动态 | 已接入完整评论/动态多页长图保存，含附件与明确长度预算；我的评论另存本机 JSON；[PiliContentImageExport.swift](../bili/Sources/Services/PiliContentImageExport.swift)、[PiliContentImageExportView.swift](../bili/Sources/Features/Dynamic/PiliContentImageExportView.swift) |
| 36 | 高级弹幕 | 已接入 mode 7 路径/旋转/透明度及会员彩色弹幕；不执行任意脚本弹幕；[DanmakuService.swift](../bili/Sources/Services/DanmakuService.swift) |
| 37 | 取消/置顶评论 | 已接入赞/踩互斥、删除、内容作者置顶/取消、举报；视频/用户使用官方隔离账号表单；[BiliAPIClient+PiliCommentActions.swift](../bili/Sources/Services/BiliAPIClient+PiliCommentActions.swift)、[PiliContentReportView.swift](../bili/Sources/Features/Mine/PiliContentReportView.swift) |
| 38 | 记笔记 | 已接入原生文本笔记/草稿/列表/发布/删除，完整富文本复用官方编辑页；不是本地 Swift 富文本编辑器；[PiliNotesViews.swift](../bili/Sources/Features/Mine/PiliNotesViews.swift)、[PiliAccountWebView.swift](../bili/Sources/Features/Mine/PiliAccountWebView.swift) |
| 39 | 多账号支持 | 已接入主账号/播放/动态/互动/评论读取账号分配和凭据版本隔离；[MultiAccountExperimentSettingsView.swift](../bili/Sources/Features/Mine/MultiAccountExperimentSettingsView.swift) |
| 40 | 屏蔽带货动态/评论 | 已接入商品动态/评论过滤、关键词与 UP 主屏蔽；[MineContentFilterSettingsView.swift](../bili/Sources/Features/Mine/MineContentFilterSettingsView.swift) |
| 41 | 互动视频 | 已接入复杂条件/隐藏变量、限时默认选项、自动节点、画面热点、结局/回溯限制和快照；模拟器交互回归，线上图待验收；[PiliInteractiveController.swift](../bili/Sources/Features/Player/PiliInteractiveController.swift)、[PiliInteractiveViews.swift](../bili/Sources/Features/Player/PiliInteractiveViews.swift) |
| 42 | 发评/动态反诈 | 已接入发评/动态游客可见性检查；结果不将审核延迟断言为欺诈；[PiliVisibilityCheck.swift](../bili/Sources/Services/PiliVisibilityCheck.swift)、[PiliVisibilityCheckView.swift](../bili/Sources/Features/Mine/PiliVisibilityCheckView.swift) |
| 43 | 高能进度条 | 已接入高能曲线、章节跳转、staff、标签及番剧 clip；曲线采样和响应体有上界；[BiliAPIClient+PiliPlayerMetadata.swift](../bili/Sources/Services/BiliAPIClient+PiliPlayerMetadata.swift)、[PiliPlayerMetadata.swift](../bili/Sources/Models/PiliPlayerMetadata.swift) |
| 44 | 滑动跳转预览视频缩略图 | 已接入拖动进度时视频缩略图预览；[PlayerStateViewModel.swift](../bili/Sources/Features/Player/PlayerStateViewModel.swift) |
| 45 | Live Photo | 已接入 JPEG/MOV 成对 Live Photo 编码及系统保存，测试真实媒体元数据；照片库写入待真机；[PiliLivePhotoEncoder.swift](../bili/Sources/Services/PiliLivePhotoEncoder.swift) |
| 46 | 复制/移动/排序收藏夹/稍后再看视频 | 已接入收藏夹编辑/封面/排序、内容搜索/排序/多选/复制/移动/移除、清理确认；[PiliFavoriteFoldersView.swift](../bili/Sources/Features/Mine/PiliFavoriteFoldersView.swift)、[PiliFavoriteItemsView.swift](../bili/Sources/Features/Mine/PiliFavoriteItemsView.swift) |
| 47 | 超分辨率 | iOS 对应实现：MetalFX SDR 空间超分，有分辨率/队列/温控边界；不是原版 mpv 着色器，HDR/不支持设备自动回退；[PiliSuperResolutionView.swift](../bili/Sources/Features/Player/PiliSuperResolutionView.swift) |
| 48 | 合并弹幕 | 已接入同文弹幕窗口合并、发送者去重和即时切换；核心边界测试；[DanmakuService.swift](../bili/Sources/Services/DanmakuService.swift) |
| 49 | 会员彩色弹幕 | 已接入 mode 7 路径/旋转/透明度及会员彩色弹幕；不执行任意脚本弹幕；[DanmakuService.swift](../bili/Sources/Services/DanmakuService.swift) |
| 50 | 播放全部/继续播放/倒序播放 | 已接入多 P/番剧/收藏/稍后再看/UP 合集、继续/顺序/倒序/循环、完整分页队列；[PiliPlaybackQueue.swift](../bili/Sources/Models/PiliPlaybackQueue.swift)、[PiliPlaybackToolsView.swift](../bili/Sources/Features/Player/PiliPlaybackToolsView.swift) |
| 51 | Cookie登录 | 已接入手动 Cookie 粘贴，先验证账号再保存；[PiliCookieLoginView.swift](../bili/Sources/Features/Mine/PiliCookieLoginView.swift) |
| 52 | 显示视频分段信息 | 已接入高能曲线、章节跳转、staff、标签及番剧 clip；曲线采样和响应体有上界；[BiliAPIClient+PiliPlayerMetadata.swift](../bili/Sources/Services/BiliAPIClient+PiliPlayerMetadata.swift)、[PiliPlayerMetadata.swift](../bili/Sources/Models/PiliPlayerMetadata.swift) |
| 53 | 调节字幕大小 | 已接入在线/离线/游客字幕、双语、颜色/字号/位置/延迟、SRT/VTT 导入导出、跳转和静音自动策略；[PiliSubtitleController.swift](../bili/Sources/Features/Player/PiliSubtitleController.swift)、[PiliSubtitleViews.swift](../bili/Sources/Features/Player/PiliSubtitleViews.swift)、[PiliSubtitleAudibility.swift](../bili/Sources/Features/Player/PiliSubtitleAudibility.swift) |
| 54 | 调节全屏弹幕大小 | 已接入独立全屏弹幕字号，在线/离线/直播使用同一选项；[MinePlaybackSettingsView.swift](../bili/Sources/Features/Mine/MinePlaybackSettingsView.swift) |
| 55 | 收藏夹/稍后再看多选删除 | 已接入收藏夹编辑/封面/排序、内容搜索/排序/多选/复制/移动/移除、清理确认；[PiliFavoriteFoldersView.swift](../bili/Sources/Features/Mine/PiliFavoriteFoldersView.swift)、[PiliFavoriteItemsView.swift](../bili/Sources/Features/Mine/PiliFavoriteItemsView.swift) |
| 56 | 搜索用户动态 | 已接入用户动态关键词搜索，支持页码/offset 分页；[UploaderDynamicsSection.swift](../bili/Sources/Features/Uploader/UploaderDynamicsSection.swift) |
| 57 | 直播弹幕 | 已接入直播弹幕、过滤/屏蔽/举报/回复/点赞，解压/消息数量与嵌套深度限制；[LiveDanmakuService.swift](../bili/Sources/Services/LiveDanmakuService.swift)、[PiliLiveChatViews.swift](../bili/Sources/Features/Live/PiliLiveChatViews.swift) |
| 58 | 修改头像/用户名/签名/性别/生日 | 已接入头像裁剪/上传、昵称/签名/性别/生日；昵称消耗确认与身份校验；[PiliProfileView.swift](../bili/Sources/Features/Mine/PiliProfileView.swift) |
| 59 | 创建/编辑/删除收藏夹 | 已接入收藏夹编辑/封面/排序、内容搜索/排序/多选/复制/移动/移除、清理确认；[PiliFavoriteFoldersView.swift](../bili/Sources/Features/Mine/PiliFavoriteFoldersView.swift)、[PiliFavoriteItemsView.swift](../bili/Sources/Features/Mine/PiliFavoriteItemsView.swift) |
| 60 | 评论楼中楼查看对话 | 已接入楼中楼树状/平铺、对话、定位、热度/时间、折叠及分页，缺父/循环图测试；[PiliCommentTreeRows.swift](../bili/Sources/Features/Dynamic/PiliCommentTreeRows.swift) |
| 61 | 评论楼中楼定位点击查看的评论 | 已接入楼中楼树状/平铺、对话、定位、热度/时间、折叠及分页，缺父/循环图测试；[PiliCommentTreeRows.swift](../bili/Sources/Features/Dynamic/PiliCommentTreeRows.swift) |
| 62 | 评论楼中楼按热度/时间排序 | 已接入楼中楼树状/平铺、对话、定位、热度/时间、折叠及分页，缺父/循环图测试；[PiliCommentTreeRows.swift](../bili/Sources/Features/Dynamic/PiliCommentTreeRows.swift) |
| 63 | 评论点踩 | 已接入赞/踩互斥、删除、内容作者置顶/取消、举报；视频/用户使用官方隔离账号表单；[BiliAPIClient+PiliCommentActions.swift](../bili/Sources/Services/BiliAPIClient+PiliCommentActions.swift)、[PiliContentReportView.swift](../bili/Sources/Features/Mine/PiliContentReportView.swift) |
| 64 | 私信发图 | 已接入消息中心/系统通知收件箱、私信图文、撤回、会话置顶/删除/免打扰及折叠分组；不表示 APNs 推送服务；[AccountMessageService.swift](../bili/Sources/Services/AccountMessageService.swift)、[AccountMessageCenterView.swift](../bili/Sources/Features/Mine/AccountMessageCenterView.swift) |
| 65 | 投币动画 | 已接入点赞/投币/收藏与三连、番剧分集互动及反馈动画；确认服务端成功后更新；[PiliVideoExtras.swift](../bili/Sources/Models/PiliVideoExtras.swift) |
| 66 | 取消/追番，更新追番状态 | 已接入追番/取消与想看/在看/看过状态；[PiliVideoExtras.swift](../bili/Sources/Models/PiliVideoExtras.swift) |
| 67 | 取消/订阅合集 | 已接入合集订阅/取消及状态读取；[PiliUGCSeason.swift](../bili/Sources/Models/PiliUGCSeason.swift) |
| 68 | SponsorBlock | 已接入分类自动/手动/禁用、跳过/静音/整集标记/高光、预览、投票/分类修正/提交；社区写入仅用户确认时发生；[PiliSponsorViews.swift](../bili/Sources/Features/VideoDetail/PiliSponsorViews.swift)、[PiliSponsorPreferences.swift](../bili/Sources/Services/PiliSponsorPreferences.swift) |
| 69 | 显示视频完整合集 | 已接入多 P/番剧/收藏/稍后再看/UP 合集、继续/顺序/倒序/循环、完整分页队列；[PiliPlaybackQueue.swift](../bili/Sources/Models/PiliPlaybackQueue.swift)、[PiliPlaybackToolsView.swift](../bili/Sources/Features/Player/PiliPlaybackToolsView.swift) |
| 70 | 三连动画 | 已接入点赞/投币/收藏与三连、番剧分集互动及反馈动画；确认服务端成功后更新；[PiliVideoExtras.swift](../bili/Sources/Models/PiliVideoExtras.swift) |
| 71 | 番剧三连 | 已接入点赞/投币/收藏与三连、番剧分集互动及反馈动画；确认服务端成功后更新；[PiliVideoExtras.swift](../bili/Sources/Models/PiliVideoExtras.swift) |
| 72 | 带图评论 | 已接入动态/评论富文本、表情、图片、@ 用户及账号绑定提交；[PiliDynamicComposer.swift](../bili/Sources/Features/Dynamic/PiliDynamicComposer.swift)、[BiliAPIClient+Comments.swift](../bili/Sources/Services/BiliAPIClient+Comments.swift) |
| 73 | 视频TAG | 已接入视频 TAG 浏览和搜索跳转；[PiliPlayerMetadata.swift](../bili/Sources/Models/PiliPlayerMetadata.swift) |
| 74 | 筛选搜索 | 已接入多内容类型搜索、排序/时长筛选、热搜/历史/默认词与无痕不留记录；[SearchViewModel.swift](../bili/Sources/Features/Search/SearchViewModel.swift)、[PiliSearchDiscovery.swift](../bili/Sources/Features/Search/PiliSearchDiscovery.swift) |
| 75 | 转发动态 | 已接入发布、转发、编辑、删除、置顶/取消置顶，失败草稿与身份校验；[PiliDynamicComposer.swift](../bili/Sources/Features/Dynamic/PiliDynamicComposer.swift)、[PiliDynamicManagement.swift](../bili/Sources/Features/Dynamic/PiliDynamicManagement.swift) |
| 76 | 合集图片 | 已接入封面、合集图片、评论/笔记图片预览和系统保存；[ZoomyImagePreview.swift](../bili/Sources/DesignSystem/ZoomyImagePreview.swift) |
| 77 | 删除/置顶/撤回私信 | 已接入消息中心/系统通知收件箱、私信图文、撤回、会话置顶/删除/免打扰及折叠分组；不表示 APNs 推送服务；[AccountMessageService.swift](../bili/Sources/Services/AccountMessageService.swift)、[AccountMessageCenterView.swift](../bili/Sources/Features/Mine/AccountMessageCenterView.swift) |
| 78 | 举报用户/评论/视频/动态 | 已接入赞/踩互斥、删除、内容作者置顶/取消、举报；视频/用户使用官方隔离账号表单；[BiliAPIClient+PiliCommentActions.swift](../bili/Sources/Services/BiliAPIClient+PiliCommentActions.swift)、[PiliContentReportView.swift](../bili/Sources/Features/Mine/PiliContentReportView.swift) |
| 79 | 删除/发布/置顶文本/图片动态 | 已接入发布、转发、编辑、删除、置顶/取消置顶，失败草稿与身份校验；[PiliDynamicComposer.swift](../bili/Sources/Features/Dynamic/PiliDynamicComposer.swift)、[PiliDynamicManagement.swift](../bili/Sources/Features/Dynamic/PiliDynamicManagement.swift) |
| 80 | 其他 | 上游分组标题，不计为一项独立功能 |
| 81 | 专栏界面 | 已接入用户图文、专栏/新图文正文、图片/公式/Live Photo、评论与互动；旧 HTML 使用禁用脚本的排版容器；[PiliArticleView.swift](../bili/Sources/Features/Dynamic/PiliArticleView.swift)、[PiliUserArticlesView.swift](../bili/Sources/Features/Uploader/PiliUserArticlesView.swift) |
| 82 | 私信界面 | 已接入消息中心/系统通知收件箱、私信图文、撤回、会话置顶/删除/免打扰及折叠分组；不表示 APNs 推送服务；[AccountMessageService.swift](../bili/Sources/Services/AccountMessageService.swift)、[AccountMessageCenterView.swift](../bili/Sources/Features/Mine/AccountMessageCenterView.swift) |
| 83 | 收藏面板 | 已接入收藏选择面板，AU 音频按 type=12 收藏；[PiliFavoriteItemsView.swift](../bili/Sources/Features/Mine/PiliFavoriteItemsView.swift)、[PiliAudioView.swift](../bili/Sources/Features/Player/PiliAudioView.swift) |
| 84 | PIP | 已接入 AVPlayer 原生 PiP/系统控制；iOS 浮窗不叠加 SwiftUI 弹幕和双语字幕，原版 iOS 同样仅视频画面；[PlayerStateViewModel.swift](../bili/Sources/Features/Player/PlayerStateViewModel.swift) |
| 85 | 视频封面 | 已接入封面、合集图片、评论/笔记图片预览和系统保存；[ZoomyImagePreview.swift](../bili/Sources/DesignSystem/ZoomyImagePreview.swift) |
| 86 | 回复界面 | 已接入楼中楼树状/平铺、对话、定位、热度/时间、折叠及分页，缺父/循环图测试；[PiliCommentTreeRows.swift](../bili/Sources/Features/Dynamic/PiliCommentTreeRows.swift) |
| 87 | 系统通知 | 已接入消息中心/系统通知收件箱、私信图文、撤回、会话置顶/删除/免打扰及折叠分组；不表示 APNs 推送服务；[AccountMessageService.swift](../bili/Sources/Services/AccountMessageService.swift)、[AccountMessageCenterView.swift](../bili/Sources/Features/Mine/AccountMessageCenterView.swift) |
| 88 | 评论显示 | 已接入楼中楼树状/平铺、对话、定位、热度/时间、折叠及分页，缺父/循环图测试；[PiliCommentTreeRows.swift](../bili/Sources/Features/Dynamic/PiliCommentTreeRows.swift) |
| 89 | 亮度调节 | 已接入亮度/音量、左右拖动、双击暂停/两侧跳转、中间上滑全屏/下滑退出、倍速/长按；可选触感；[PiliPlaybackGesturePolicy.swift](../bili/Sources/Features/Player/PiliPlaybackGesturePolicy.swift)、[NativePlayerSurfaceGestureController.swift](../bili/Sources/Features/Player/NativePlayerSurfaceGestureController.swift) |
| 90 | 视频播放 | 已接入 AVPlayer、画质/音质/编码选择及预设；硬解/格式/HDR 取决于系统与设备，权限不解锁；[PlayerStateViewModel.swift](../bili/Sources/Features/Player/PlayerStateViewModel.swift)、[VideoCodecSelectionSettingsView.swift](../bili/Sources/Features/Mine/VideoCodecSelectionSettingsView.swift) |
| 91 | 视频staff | 已接入高能曲线、章节跳转、staff、标签及番剧 clip；曲线采样和响应体有上界；[BiliAPIClient+PiliPlayerMetadata.swift](../bili/Sources/Services/BiliAPIClient+PiliPlayerMetadata.swift)、[PiliPlayerMetadata.swift](../bili/Sources/Models/PiliPlayerMetadata.swift) |
| 92 | 防止bottomsheet遮挡全屏视频 | 已接入横屏玻璃控件、锁定、菜单布局及全屏导航恢复；7 项 UI 自动化含横屏播放器；[PiliLiquidGlass.swift](../bili/Sources/DesignSystem/PiliLiquidGlass.swift) |
| 93 | 其他 | 上游分组标题，不计为一项独立功能 |
| 94 | 番剧分集点赞/投币/收藏 | 已接入点赞/投币/收藏与三连、番剧分集互动及反馈动画；确认服务端成功后更新；[PiliVideoExtras.swift](../bili/Sources/Models/PiliVideoExtras.swift) |
| 95 | bugs | 上游分组标题，不计为一项独立功能 |
| 96 | 推荐视频列表(app端) | 已接入 Web/App 推荐、热门、每周必看、入站必刷和分区/番剧排行；[PiliDiscovery.swift](../bili/Sources/Services/PiliDiscovery.swift) |
| 97 | 最热视频列表 | 已接入 Web/App 推荐、热门、每周必看、入站必刷和分区/番剧排行；[PiliDiscovery.swift](../bili/Sources/Services/PiliDiscovery.swift) |
| 98 | 热门直播 | 已接入直播分区、推荐与关注直播、分区榜单及房间导航；[PiliLiveExploreView.swift](../bili/Sources/Features/Live/PiliLiveExploreView.swift)、[LiveFeedView.swift](../bili/Sources/Features/Live/LiveFeedView.swift) |
| 99 | 番剧列表 | 已接入六类番剧/影视索引、服务端筛选/排序、分页与时间表；[PiliPGCCatalogue.swift](../bili/Sources/Services/PiliPGCCatalogue.swift) |
| 100 | 屏蔽黑名单内用户视频 | 已接入账号黑名单同步、推荐/相关视频过滤，本机拉黑立即生效；[PiliBlacklistedCreators.swift](../bili/Sources/Services/PiliBlacklistedCreators.swift) |
| 101 | 无痕模式（播放视为未登录） | 已接入无痕播放匿名凭据/缓存隔离、游客推荐及历史停止；AU 也使用播放身份；[BiliAPIClient+RequestContexts.swift](../bili/Sources/Services/BiliAPIClient+RequestContexts.swift)、[LibraryStore.swift](../bili/Sources/Storage/LibraryStore.swift) |
| 102 | 游客模式（推荐视为未登录） | 已接入无痕播放匿名凭据/缓存隔离、游客推荐及历史停止；AU 也使用播放身份；[BiliAPIClient+RequestContexts.swift](../bili/Sources/Services/BiliAPIClient+RequestContexts.swift)、[LibraryStore.swift](../bili/Sources/Storage/LibraryStore.swift) |
| 103 | 用户相关 | 上游分组标题，不计为一项独立功能 |
| 104 | 粉丝、关注用户、拉黑用户查看 | 已接入粉丝/关注/黑名单分页、搜索、关注/取关/移除粉丝及确认操作；[PiliRelationsView.swift](../bili/Sources/Features/Mine/PiliRelationsView.swift)、[BiliAPIClient+PiliRelations.swift](../bili/Sources/Services/BiliAPIClient+PiliRelations.swift) |
| 105 | 用户主页查看 | 已接入用户主页、稿件/动态/合集/图文与更多空间内容、关系和徽章；[UploaderView.swift](../bili/Sources/Features/Uploader/UploaderView.swift)、[PiliMemberExtrasView.swift](../bili/Sources/Features/Uploader/PiliMemberExtrasView.swift) |
| 106 | 关注/取关用户 | 已接入粉丝/关注/黑名单分页、搜索、关注/取关/移除粉丝及确认操作；[PiliRelationsView.swift](../bili/Sources/Features/Mine/PiliRelationsView.swift)、[BiliAPIClient+PiliRelations.swift](../bili/Sources/Services/BiliAPIClient+PiliRelations.swift) |
| 107 | 离线缓存 | 已接入后台下载、续传/校验、双轨合并、音频/视频分组、批量下载与导出、离线播放器；后台调度待真机；[PiliOfflineStore.swift](../bili/Sources/Services/PiliOfflineStore.swift)、[PiliOfflinePlayerScreen.swift](../bili/Sources/Features/Player/PiliOfflinePlayerScreen.swift) |
| 108 | 稍后再看 | 已接入全部/未看完、搜索、添加时间正反序、多选管理与分页连播；[PiliWatchLaterToolsView.swift](../bili/Sources/Features/Mine/PiliWatchLaterToolsView.swift)、[BiliAPIClient+PiliWatchLater.swift](../bili/Sources/Services/BiliAPIClient+PiliWatchLater.swift) |
| 109 | 观看记录 | 已接入历史分类/搜索/分页/批量移除/清空、云端暂停，专栏走原生正文；[PiliHistoryView.swift](../bili/Sources/Features/Mine/PiliHistoryView.swift) |
| 110 | 我的收藏 | 已接入收藏夹编辑/封面/排序、内容搜索/排序/多选/复制/移动/移除、清理确认；[PiliFavoriteFoldersView.swift](../bili/Sources/Features/Mine/PiliFavoriteFoldersView.swift)、[PiliFavoriteItemsView.swift](../bili/Sources/Features/Mine/PiliFavoriteItemsView.swift) |
| 111 | 站内私信 | 已接入消息中心/系统通知收件箱、私信图文、撤回、会话置顶/删除/免打扰及折叠分组；不表示 APNs 推送服务；[AccountMessageService.swift](../bili/Sources/Services/AccountMessageService.swift)、[AccountMessageCenterView.swift](../bili/Sources/Features/Mine/AccountMessageCenterView.swift) |
| 112 | 动态相关 | 上游分组标题，不计为一项独立功能 |
| 113 | 全部、投稿、番剧分类查看 | 已接入动态分类独立请求/缓存与评论读取/回复；[PiliContentDraft.swift](../bili/Sources/Models/PiliContentDraft.swift)、[DynamicComments.swift](../bili/Sources/Features/Dynamic/DynamicComments.swift) |
| 114 | 动态评论查看 | 已接入动态分类独立请求/缓存与评论读取/回复；[PiliContentDraft.swift](../bili/Sources/Models/PiliContentDraft.swift)、[DynamicComments.swift](../bili/Sources/Features/Dynamic/DynamicComments.swift) |
| 115 | 动态评论回复功能 | 已接入动态分类独立请求/缓存与评论读取/回复；[PiliContentDraft.swift](../bili/Sources/Models/PiliContentDraft.swift)、[DynamicComments.swift](../bili/Sources/Features/Dynamic/DynamicComments.swift) |
| 116 | 视频播放相关 | 上游分组标题，不计为一项独立功能 |
| 117 | 双击快进/快退 | 已接入亮度/音量、左右拖动、双击暂停/两侧跳转、中间上滑全屏/下滑退出、倍速/长按；可选触感；[PiliPlaybackGesturePolicy.swift](../bili/Sources/Features/Player/PiliPlaybackGesturePolicy.swift)、[NativePlayerSurfaceGestureController.swift](../bili/Sources/Features/Player/NativePlayerSurfaceGestureController.swift) |
| 118 | 双击播放/暂停 | 已接入亮度/音量、左右拖动、双击暂停/两侧跳转、中间上滑全屏/下滑退出、倍速/长按；可选触感；[PiliPlaybackGesturePolicy.swift](../bili/Sources/Features/Player/PiliPlaybackGesturePolicy.swift)、[NativePlayerSurfaceGestureController.swift](../bili/Sources/Features/Player/NativePlayerSurfaceGestureController.swift) |
| 119 | 垂直方向调节亮度/音量 | 已接入亮度/音量、左右拖动、双击暂停/两侧跳转、中间上滑全屏/下滑退出、倍速/长按；可选触感；[PiliPlaybackGesturePolicy.swift](../bili/Sources/Features/Player/PiliPlaybackGesturePolicy.swift)、[NativePlayerSurfaceGestureController.swift](../bili/Sources/Features/Player/NativePlayerSurfaceGestureController.swift) |
| 120 | 垂直方向上滑全屏、下滑退出全屏 | 已接入亮度/音量、左右拖动、双击暂停/两侧跳转、中间上滑全屏/下滑退出、倍速/长按；可选触感；[PiliPlaybackGesturePolicy.swift](../bili/Sources/Features/Player/PiliPlaybackGesturePolicy.swift)、[NativePlayerSurfaceGestureController.swift](../bili/Sources/Features/Player/NativePlayerSurfaceGestureController.swift) |
| 121 | 水平方向手势快进/快退 | 已接入亮度/音量、左右拖动、双击暂停/两侧跳转、中间上滑全屏/下滑退出、倍速/长按；可选触感；[PiliPlaybackGesturePolicy.swift](../bili/Sources/Features/Player/PiliPlaybackGesturePolicy.swift)、[NativePlayerSurfaceGestureController.swift](../bili/Sources/Features/Player/NativePlayerSurfaceGestureController.swift) |
| 122 | 全屏方向设置 | 已接入设备/固定左右全屏方向、fit/fill/stretch/宽高适应、自动全屏和横屏布局；[MinePlaybackSettingsView.swift](../bili/Sources/Features/Mine/MinePlaybackSettingsView.swift) |
| 123 | 倍速选择/长按2倍速 | 已接入亮度/音量、左右拖动、双击暂停/两侧跳转、中间上滑全屏/下滑退出、倍速/长按；可选触感；[PiliPlaybackGesturePolicy.swift](../bili/Sources/Features/Player/PiliPlaybackGesturePolicy.swift)、[NativePlayerSurfaceGestureController.swift](../bili/Sources/Features/Player/NativePlayerSurfaceGestureController.swift) |
| 124 | 硬件加速（视机型而定） | 已接入 AVPlayer、画质/音质/编码选择及预设；硬解/格式/HDR 取决于系统与设备，权限不解锁；[PlayerStateViewModel.swift](../bili/Sources/Features/Player/PlayerStateViewModel.swift)、[VideoCodecSelectionSettingsView.swift](../bili/Sources/Features/Mine/VideoCodecSelectionSettingsView.swift) |
| 125 | 画质选择（高清画质未解锁） | 已接入 AVPlayer、画质/音质/编码选择及预设；硬解/格式/HDR 取决于系统与设备，权限不解锁；[PlayerStateViewModel.swift](../bili/Sources/Features/Player/PlayerStateViewModel.swift)、[VideoCodecSelectionSettingsView.swift](../bili/Sources/Features/Mine/VideoCodecSelectionSettingsView.swift) |
| 126 | 音质选择（视视频而定） | 已接入 AVPlayer、画质/音质/编码选择及预设；硬解/格式/HDR 取决于系统与设备，权限不解锁；[PlayerStateViewModel.swift](../bili/Sources/Features/Player/PlayerStateViewModel.swift)、[VideoCodecSelectionSettingsView.swift](../bili/Sources/Features/Mine/VideoCodecSelectionSettingsView.swift) |
| 127 | 解码格式选择（视视频而定） | 已接入 AVPlayer、画质/音质/编码选择及预设；硬解/格式/HDR 取决于系统与设备，权限不解锁；[PlayerStateViewModel.swift](../bili/Sources/Features/Player/PlayerStateViewModel.swift)、[VideoCodecSelectionSettingsView.swift](../bili/Sources/Features/Mine/VideoCodecSelectionSettingsView.swift) |
| 128 | 弹幕 | 已接入在线/离线/直播弹幕、字号/区域/密度/过滤/颜色/速度及高级弹幕；[DanmakuService.swift](../bili/Sources/Services/DanmakuService.swift) |
| 129 | 字幕 | 已接入在线/离线/游客字幕、双语、颜色/字号/位置/延迟、SRT/VTT 导入导出、跳转和静音自动策略；[PiliSubtitleController.swift](../bili/Sources/Features/Player/PiliSubtitleController.swift)、[PiliSubtitleViews.swift](../bili/Sources/Features/Player/PiliSubtitleViews.swift)、[PiliSubtitleAudibility.swift](../bili/Sources/Features/Player/PiliSubtitleAudibility.swift) |
| 130 | 记忆播放 | 已接入本机/云端进度和离线恢复、切集/账号版本检查；[LibraryStore.swift](../bili/Sources/Storage/LibraryStore.swift)、[PiliOfflinePlaybackModel.swift](../bili/Sources/Features/Player/PiliOfflinePlaybackModel.swift) |
| 131 | 视频比例：高度/宽度适应、填充、包含等 | 已接入设备/固定左右全屏方向、fit/fill/stretch/宽高适应、自动全屏和横屏布局；[MinePlaybackSettingsView.swift](../bili/Sources/Features/Mine/MinePlaybackSettingsView.swift) |
| 132 | 搜索相关 | 上游分组标题，不计为一项独立功能 |
| 133 | 热搜 | 已接入多内容类型搜索、排序/时长筛选、热搜/历史/默认词与无痕不留记录；[SearchViewModel.swift](../bili/Sources/Features/Search/SearchViewModel.swift)、[PiliSearchDiscovery.swift](../bili/Sources/Features/Search/PiliSearchDiscovery.swift) |
| 134 | 搜索历史 | 已接入多内容类型搜索、排序/时长筛选、热搜/历史/默认词与无痕不留记录；[SearchViewModel.swift](../bili/Sources/Features/Search/SearchViewModel.swift)、[PiliSearchDiscovery.swift](../bili/Sources/Features/Search/PiliSearchDiscovery.swift) |
| 135 | 默认搜索词 | 已接入多内容类型搜索、排序/时长筛选、热搜/历史/默认词与无痕不留记录；[SearchViewModel.swift](../bili/Sources/Features/Search/SearchViewModel.swift)、[PiliSearchDiscovery.swift](../bili/Sources/Features/Search/PiliSearchDiscovery.swift) |
| 136 | 投稿、番剧、直播间、用户搜索 | 已接入多内容类型搜索、排序/时长筛选、热搜/历史/默认词与无痕不留记录；[SearchViewModel.swift](../bili/Sources/Features/Search/SearchViewModel.swift)、[PiliSearchDiscovery.swift](../bili/Sources/Features/Search/PiliSearchDiscovery.swift) |
| 137 | 视频搜索排序、按时长筛选 | 已接入多内容类型搜索、排序/时长筛选、热搜/历史/默认词与无痕不留记录；[SearchViewModel.swift](../bili/Sources/Features/Search/SearchViewModel.swift)、[PiliSearchDiscovery.swift](../bili/Sources/Features/Search/PiliSearchDiscovery.swift) |
| 138 | 视频详情页相关 | 上游分组标题，不计为一项独立功能 |
| 139 | 视频选集(分p)切换 | 已接入多 P 选择、上一/下一、详情队列与连播；[PiliPlaybackQueue.swift](../bili/Sources/Models/PiliPlaybackQueue.swift) |
| 140 | 点赞、投币、收藏/取消收藏 | 已接入点赞/投币/收藏与三连、番剧分集互动及反馈动画；确认服务端成功后更新；[PiliVideoExtras.swift](../bili/Sources/Models/PiliVideoExtras.swift) |
| 141 | 相关视频查看 | 已接入相关视频及过滤，切换视频保持队列和播放意图；[VideoDetailView.swift](../bili/Sources/Features/VideoDetail/VideoDetailView.swift) |
| 142 | 评论用户身份标识 | 已接入会员/认证/UP 主身份标识；[PiliCommentTreeRows.swift](../bili/Sources/Features/Dynamic/PiliCommentTreeRows.swift) |
| 143 | 评论(排序)查看、二楼评论查看 | 已接入楼中楼树状/平铺、对话、定位、热度/时间、折叠及分页，缺父/循环图测试；[PiliCommentTreeRows.swift](../bili/Sources/Features/Dynamic/PiliCommentTreeRows.swift) |
| 144 | 主楼、二楼评论回复功能 | 已接入楼中楼树状/平铺、对话、定位、热度/时间、折叠及分页，缺父/循环图测试；[PiliCommentTreeRows.swift](../bili/Sources/Features/Dynamic/PiliCommentTreeRows.swift) |
| 145 | 评论点赞 | 已接入赞/踩互斥、删除、内容作者置顶/取消、举报；视频/用户使用官方隔离账号表单；[BiliAPIClient+PiliCommentActions.swift](../bili/Sources/Services/BiliAPIClient+PiliCommentActions.swift)、[PiliContentReportView.swift](../bili/Sources/Features/Mine/PiliContentReportView.swift) |
| 146 | 评论笔记图片查看、保存 | 已接入封面、合集图片、评论/笔记图片预览和系统保存；[ZoomyImagePreview.swift](../bili/Sources/DesignSystem/ZoomyImagePreview.swift) |
| 147 | 设置相关 | 上游分组标题，不计为一项独立功能 |
| 148 | 画质、音质、解码方式预设 | 已接入 AVPlayer、画质/音质/编码选择及预设；硬解/格式/HDR 取决于系统与设备，权限不解锁；[PlayerStateViewModel.swift](../bili/Sources/Features/Player/PlayerStateViewModel.swift)、[VideoCodecSelectionSettingsView.swift](../bili/Sources/Features/Mine/VideoCodecSelectionSettingsView.swift) |
| 149 | 图片质量设定 | 已接入图片质量、亮暗/跟随系统、触感和高刷新率偏好；温控/低电量/后台停止高帧率回调，系统决定实际帧率；[MineDisplaySettingsSection.swift](../bili/Sources/Features/Mine/MineDisplaySettingsSection.swift) |
| 150 | 主题模式：亮色/暗色/跟随系统 | 已接入图片质量、亮暗/跟随系统、触感和高刷新率偏好；温控/低电量/后台停止高帧率回调，系统决定实际帧率；[MineDisplaySettingsSection.swift](../bili/Sources/Features/Mine/MineDisplaySettingsSection.swift) |
| 151 | 震动反馈(可选) | 已接入图片质量、亮暗/跟随系统、触感和高刷新率偏好；温控/低电量/后台停止高帧率回调，系统决定实际帧率；[MineDisplaySettingsSection.swift](../bili/Sources/Features/Mine/MineDisplaySettingsSection.swift) |
| 152 | 高帧率 | 已接入图片质量、亮暗/跟随系统、触感和高刷新率偏好；温控/低电量/后台停止高帧率回调，系统决定实际帧率；[MineDisplaySettingsSection.swift](../bili/Sources/Features/Mine/MineDisplaySettingsSection.swift) |
| 153 | 自动全屏 | 已接入设备/固定左右全屏方向、fit/fill/stretch/宽高适应、自动全屏和横屏布局；[MinePlaybackSettingsView.swift](../bili/Sources/Features/Mine/MinePlaybackSettingsView.swift) |
| 154 | 横屏适配 | 已接入设备/固定左右全屏方向、fit/fill/stretch/宽高适应、自动全屏和横屏布局；[MinePlaybackSettingsView.swift](../bili/Sources/Features/Mine/MinePlaybackSettingsView.swift) |

## README 之外的页面核对

| 原版页面 | 本仓库入口及实现 |
| --- | --- |
| audio / music | AU 深链原生播放器、BGM 详情/想听/MV/热度与相关视频；`PiliAudioView` / `PiliSupplementView` |
| bubble / match_info | 小站分类/排序/分页，赛事比分/直播/讨论；原链接直接进入原生页 |
| member_audio / coin_arc / like_arc / comic / pgc / cheese / guard / upower_rank / shop | 用户主页 → 更多空间内容；漫画阅读和商品详情按原版使用官方网页，未实现购买流程 |
| fav/pgc、fav/article、fav/topic、subscription/detail | 我的 → 追番与其他收藏；追番/追剧状态筛选与多选更改、图文/话题收藏、订阅的合集/收藏夹与取消订阅 |
| member_favorite | 用户公开收藏夹、内容分页/搜索/排序/订阅，避免展示其他人的编辑/删除操作 |
| popular_series / popular_precious / rank / pgc_index | 首页内容菜单 → 每周必看与排行榜 / 番剧与影视 |
| pgc_review | 番剧信息 → 评分与点评：短评、长评、评分/编辑/删除、赞/踩 |
| coin_log / exp_log / login_log / login_devices / space_setting | 我的 → 账号记录与空间隐私；App 设备列表需要有效 App 登录凭据 |
| my_reply | 我的 → 我的评论：按互动账号隔离的本机记录、原版 JSON 导入/导出、查可见性/删除 |
| 评论/内容/手势设置 | 正文关键词过滤与嵌套预览裁剪、记录评论开关、视频/动态服务端警告提示、双指捏合退出全屏 |
| settings_search | 我的 → 搜索设置：搜索关键词并跳转对应设置分组，布局采用 iOS 表单 |

真实账号写入只在用户主动操作时发生。自动化测试使用请求桩，不发布真实动态/评论、不发真实私信、不消耗硬币或购买内容。
