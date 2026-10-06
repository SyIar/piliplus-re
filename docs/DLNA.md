# DLNA 投屏

视频详情与离线播放器提供“投屏”，我的页面提供“投屏遥控”。投屏建立独立媒体转发器，离开本机播放页面不会释放电视使用的地址。停止投屏后关闭监听、媒体路由与连接。

## 当前支持

- SSDP M-SEARCH 查找 AVTransport / MediaRenderer；按设备描述中的服务地址发送 SOAP。
- 手动输入 HTTP(S) 设备描述地址，适用于 SSDP 被路由器或签名权限限制时。需要完整描述地址，普通电视网页地址不能代替。
- 播放、暂停、停止、相对时间跳转、支持 RenderingControl 的电视音量、播放状态轮询。
- 在线 DASH 双轨转换为含音频组的 fMP4 HLS；不向电视传递 B 站凭据。
- 已下载文件提供 GET / HEAD 和 HTTP Range，不将整个视频读入内存。
- 立即到点的定时停止发送 Stop；播完当前再停依据电视位置与状态处理。请求失败保留遥控入口并显示未确认停止，关闭转发不保证电视已缓冲部分立即停止。

## iOS 本地网络与签名

Info.plist 已声明 `NSLocalNetworkUsageDescription` 和局域网 ATS 例外，首次访问时由系统询问本地网络权限。

**真机 SSDP 组播需要 Apple 授权的 `com.apple.developer.networking.multicast` 权限，以及包含该权限的有效签名描述文件。** `Config/PiliDLNA.entitlements` 提供 entitlement 文件，但默认 unsigned CI 不宣称获得该权限；为自己的开发团队取得授权后，签名构建时设置 `CODE_SIGN_ENTITLEMENTS=Config/PiliDLNA.entitlements`。不能仅编辑 entitlements 文件就取得系统授权。手动添加设备走单播，仍需本地网络访问权限。

目前选择 en* 网络接口的 RFC1918 / IPv4 链路本地地址；IPv6-only 网络待实现。控制请求禁止重定向、禁用 Cookie 与共享凭据。转发器仅绑定选中的本地地址、接收电视地址的连接，并使用随机会话路径；本地播放器的 loopback 监听规则保持不变。

## 已知缺口与验收

- 在线 HLS 要求接收端支持分片 MP4 与独立音频组；不是所有 DLNA 电视都兼容。可先选 H.264 SDR，或离线下载完成后投送合并文件。
- 当前不进行实时转码，不支持所有 FLV / 渐进式流；没有将“有音轨”与“电视可解码”混为一谈。
- 转发期间应保持 App 前台。iOS 挂起进程后不能保证转发或定时网络指令继续执行；没有使用静音音频伪造后台播放。
- 投屏队列、多 P、收藏/稍后再看/合集按需分页、上一/下一、自动切集和计时优先级已经接入 `PiliCastQueue`；互动分支在本机选择，不为电视烧录弹幕/字幕。
- 不支持 IPv6-only 局域网和实时转码；这是仍存在的网络/格式边界，不应写为全设备对等。
- 真机验收：首次权限、拒绝后恢复、设备消失、暂停/跳转/音量、关闭播放页面继续遥控、定时停止、同一电视重新投送、网络切换、HLS 声画同步、离线文件拖动及停止后不可访问。
- 自动测试：核心协议/XML/网络边界；iOS 回环 HTTP 的 HEAD/Range/随机路由；SOAP 控制地址、参数与无凭据请求。尚无真实电视验收记录。

协议资料：[Sony 的 AVTransport 示例](https://github.com/sonydevworld/audio_control_api_examples/blob/master/DLNA/AVTransport/play_file.adoc)、[Apple 本地网络隐私](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)、[Apple 组播权限](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast)。
