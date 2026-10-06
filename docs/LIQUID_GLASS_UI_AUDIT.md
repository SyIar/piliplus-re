# 全局 Liquid Glass UI 核查

2026-10-06，按用户决定停止新增功能迁移。本次工作统一已有界面，并保留签名后真机及线上账号验收的边界。

## 设计依据

布局和交互以 [原 PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus) 为参考，视觉材质使用 ChunUI。重点参照 `video_card_v.dart` / `video_popup_menu.dart` 的卡片右下角菜单，以及设置项标题在左、操作在右的结构；不宣称对 Flutter 页面逐像素复刻。

ChunUI 固定 revision `b240cbbdb9c6d7afc9f02d9ce4ddff5a25ce73bb`，依据其 [SKILL.md](https://github.com/liseami/ChunUI/blob/b240cbbdb9c6d7afc9f02d9ce4ddff5a25ce73bb/skills/chunui/SKILL.md)、presentation 和 components 规范。

- 默认品牌色为蓝色 `#3264F0`，普通表面、文字使用灰阶语义色；确认按钮及功能反馈随用户选择的主题色更新，取消保持灰阶。色调选择的八个选项在同一行等分排列。
- 文本使用 13 / 17 / 24 基线与相应粗体。`PiliTypography` 在 ChunUI 字体上保留 Dynamic Type 缩放；媒体字幕、弹幕与用户自定义颜色继续服从内容设置。
- 业务图标使用包内 Pika 资产。`PiliSymbols` 显式映射旧业务标识，`PiliIcon` 继承前景色，保证视频上的白色按钮和浅色页按钮都可辨认；系统原生 Tab 保留系统图标接口。
- 页内表单、列表及多选列表集中到 `PiliForm` / `PiliList` / `PiliSelectionList`；原生分组拥有外轮廓，组内是连续半透明材质与细分隔线，取消逐行玻璃圆角、描边和间隙，避免椭圆卡片连续堆叠。内容卡片使用 `piliGlassCard`，按钮使用原生 glass / glassProminent 或 ChunUI 控件。
- 弹层经 `PiliPresentation` 调用 ChunUI `AppHelper.presentSheet`，UIKit 管理一层 Liquid Glass 背景。内部行避免重复模糊；减少透明度时退回清晰语义底色。
- 确认反馈通过 ChunUI 公开的 `showCenterCard` 呈现，四角统一 24pt，避免系统 alert 与应用风格混用。照片选择、文件导入导出、系统分享及官方网页仍由对应系统/网页提供界面。

## 页面盘点

| 范围 | 核查与修改 |
| --- | --- |
| 首页 / 搜索 / 直播列表 | 推荐默认每行两卡，旧单列偏好首次升级转为双列，之后可手动调整；上下结构视频封面只圆顶部、底边与文字平接，玻璃与阴影归整张卡片所有；卡片右下角为独立的三点菜单，提供稍后再看、访问 UP 主、复制 BV/链接、不感兴趣；菜单点击不触发播放预热；保留原导航与浮动底栏 |
| 动态 / 评论 / UP 空间 | 动态卡片、加载失败/空态、操作按钮、回复与用户面板统一颜色、字体及图标 |
| 我的 / 设置 / 账号 | 表单与列表统一表面；菜单选值、清理/同步/应用按钮、输入框统一右对齐，精简说明；恢复设置子页标题；离线和笔记多选保留原选择绑定 |
| 播放器 / 番剧 / 直播 | 保留黑色视频画布和玻璃控制层；工具、字幕、弹幕、诊断、选集及互动面板接入统一呈现 |
| 收藏 / 下载 / 消息 / 发布 | 保留已有业务与请求逻辑；嵌套选择器、编辑页与确认动作改接 ChunUI 命令式呈现 |
| 可访问性 | 保留系统/手动字号，补全仅图标按钮的名称；支持减少透明度，保留系统减少动态效果行为 |

`Scripts/validate-ui.py` 检查业务中没有直接 SwiftUI sheet / alert / confirmationDialog、裸 Form/List、散落 SF Image 或无限重复动画，并检查 Pika 字面量映射；CI 在编译前执行。

## 交互保护

`PiliSheetSession` 让源绑定与实际关闭同步；替换 item 时旧弹层不能清空新目标；内层关闭只关闭自己的控制器。`PiliSheetOwner` 转发 ChunUI 原有编辑关闭委托，同时保留原面板高度与提交中的关闭保护；新 detent 继续携带玻璃背景。键盘布局导向关闭 `usesBottomSafeArea`，隐藏键盘时铺满底边，弹出键盘时仍避让，避免内容在 Home 指示条上方被直线截断。独立 hosting controller 显式接收应用依赖与路由上下文，不复制旧系统环境或父弹层的编辑会话。

确认卡片采用 ChunUI `showCenterCard` / `dismissCenterCard`，由公共 `ccNeoChrome` 绘制可随字号增长的主题色按钮。使用等半径圆角，避免默认底部弹窗上下圆角不同。适配器保持源绑定到动作执行结束；背景取消只清理会话，选择动作只执行一次。下载、笔记和备份的直接确认入口也使用同一适配器，不访问 ChunUI 私有状态。

## 验证与预览

[CI 37480836002](https://github.com/SyIar/piliplus-re/actions/runs/37480836002)（`871895d`）通过 39 core、839 iOS 单元、10 UI、设备 Release，已实际查看全部 18 张预览。确认双列首页、封面直角底边、连续设置分组、八色同排及蓝色/紫色主题确认正确；超大字号代码和重置按钮完整显示。该轮截图还发现手机面板的底安全区接缝，因此继续修正键盘布局导向，并增加输入框避让键盘的回归。随后按用户反馈继续统一确认四角、接入卡片菜单及整理设置操作对齐。最终提交仍须通过同一门禁。

完整门禁包含核心包测试、iOS 单元测试、`PiliLiquidGlassUITests`、设备 Release 构建和真实模拟器截图。UI 回归覆盖原有播放/字幕/评论/互动/发布路径，并增加嵌套面板、重开、替换目标、提交保护、确认取消/背景关闭/只执行一次、卡片三点菜单与播放点击分离、键盘避让、多选列表及大字设置导航。

`Scripts/capture-preview.sh` 导出首页明暗、横屏播放器、字幕、评论、互动、设置明暗、面板明暗、确认明暗与紫色主题确认，以及减少透明度/大字设置、iPad 首页、设置、面板、确认以及大字确认和卡片实际菜单的截图。预览 artifact 和最终测试状态以 [PR #4](https://github.com/SyIar/piliplus-re/pull/4) 的对应提交 [Actions](https://github.com/SyIar/piliplus-re/actions) 为准；失败构建不计为验收。

模拟器截图可检查布局与材质效果，不代表真实账号写操作、照片库、电视兼容性或真机 GPU/滚动性能已经验收。合入 main 后，完整测试和设备打包成功才生成预发布。
