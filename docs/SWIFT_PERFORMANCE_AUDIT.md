# Swift / SwiftUI 性能核查

核查日期：2026-10-06。目标项目使用 Swift 6、MainActor 默认隔离和 Approachable Concurrency；测试工具链为 Xcode 26。源码检查和模拟器回归可以发现无谓工作、检查正确性，不能推导真机 FPS、耗电或首次播放耗时改善百分比。

## 依据与适用规则

| 官方依据 | 本项目适用方式 |
| --- | --- |
| [Apple：Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness) | 主线程只承担必要 UI 工作；交互卡顿和逐帧渲染有不同预算。以主线程更新约 5 ms 为排查参考，不把它当任意设备上的绝对保证。 |
| [WWDC25：Optimize SwiftUI performance with Instruments](https://developer.apple.com/videos/play/wwdc2025/306/) | 用 SwiftUI instrument 与 Time Profiler 定位耗时 body 和无用刷新；避免在 body 中构建昂贵对象、解码图片。优化后重录相同场景。 |
| [Apple：Making changes to reduce memory use](https://developer.apple.com/documentation/xcode/making-changes-to-reduce-memory-use) | 使用 Image I/O 按目标像素缩图，控制解码后的像素量，而非只看压缩文件字节数。 |
| [Apple：Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes) | 合并小写入，图片与文字草稿分开，使用原子更新保留失败恢复能力。 |
| [Foundation：UserDefaults.synchronize](https://developer.apple.com/documentation/foundation/userdefaults/synchronize()) | Apple 明确说明此方法不必要且不应使用。正常 set 已由系统异步持久化，不应在播放历史保存路径等待同步。 |
| [Swift 6.2 Released](https://www.swift.org/blog/swift-6.2-released/) | 在新的并发规则下，async 本身不保证离开调用者 actor。明确隔离 CPU/磁盘任务，同时保持可取消性和 Sendable 边界。 |

## 已定位并处理

1. **选图完整解码**：原评论上传用 `UIImage(data:)` 后重新压缩，会先展开大照片。本轮改为 `PiliImagePreparation`，Image I/O 在独立任务里按最长边 2560 像素解码并应用 EXIF 方向，输出大小与输入大小均有限制。动态与评论共用。
2. **评论附件反复解码**：原附件条在 SwiftUI body 中构造完整 `UIImage`；改为每张附件的独立缩略图视图，异步生成最多 180 像素的预览，内容编辑不重新解码整图。
3. **新动态草稿写入**：文字变化合并 600 ms 后保存，照片以独立文件保存一次，头文件原子更新成功后清理孤立图片。回归测试把图片修改时间设为旧值，再修改正文，确认图片文件没有被重写。
4. **播放历史等待同步**：移除 `LibraryStore.persistPlaybackProgress` 的 `UserDefaults.synchronize()`，保留原有 set 和恢复数据结构。

5. **网络切换崩溃**：CI 的真实崩溃栈显示 CDN 探测在旧 URLSession 失效后创建任务。连接池原来只锁住取出 session，取出后与任务创建之间存在竞态。改为同一锁内注册 task 和替换 session；已登记任务正常完成，新任务使用新 session。图片下载同步改用这一机制，并新增并发切换与 120 次请求的回归测试。
6. **选图任务过期**：动态选图改为随 PhotosPicker 选择绑定的可取消 task；解码完成后检查取消和选择版本，防止快速切换照片时旧任务把图片追加回草稿。

缩图的收益是可验证的像素数量上界下降。没有在此报告声称实测节省多少 MB；JPEG/HEIF 解码缓冲、色彩空间、操作系统缓存和设备差异均会影响进程峰值。

## 检查后保留的已有实现

- 下载进度 `receivedProgress` 已限频到每 250 ms，且进度回调不写完整磁盘索引；不能把它误判成“每次下载回调都落盘”。
- 播放时钟已有约 0.2 s 的变化门槛、独立 render store 和 playback clock；不凭源码猜测删除这些更新，避免破坏拖动、恢复和系统媒体控制。
- 树状评论已有 ID 索引和迭代遍历，不是递归逐层扫描。继续保留深层/循环/跨页测试。
- 网络层已有读取合并、图片像素分桶/缓存和独立解码；新增 API 尽量复用，而非建立另一套无限缓存。

## 仍需真机采样的项目

- 大量历史记录 JSON 编码与离线索引同步更新的实际主线程耗时。若 Time Profiler 显示长任务，再迁移至有序写入 actor；暂停/完成/删除不能被延迟写入覆盖。
- 液态玻璃叠层、HDR/高帧率视频、密集弹幕、PiP 和后台恢复在低端设备上的 GPU/功耗表现。
- 动态/评论长列表中图片预取、富文本度量与视图更新的占比；查看 SwiftUI instrument 的因果关系后才调整观察粒度。

建议采样：同一 Release 构建、同一设备温度/电量/网络条件，分别录制首页滚动 60 s、48 MP 图片选入 9 张、密集弹幕播放 5 min、前后台/PiP 切换和离线队列；记录 Time Profiler、Allocations/VM Tracker、Hitches、File Activity 与 Energy。模拟器截图和单元测试不替代这些数据。
