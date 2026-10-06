import SwiftUI
import ChunUI

struct MinePrivacySettingsView: View {
    @AppStorage("piliplus.comments.record") private var recordsComments = true
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        PiliForm {
            Section { Toggle("保存已发送评论", isOn: $recordsComments) }
            Section { NavigationLink { PiliVisibilitySettingsView() } label: { PiliLabel("发布可见性检查", systemImage: "checkmark.shield") } }
            Section {
                Toggle(isOn: Binding(
                    get: { libraryStore.incognitoModeEnabled },
                    set: { libraryStore.setIncognitoModeEnabled($0) }
                )) {
                    MineSettingsLabel("无痕模式", systemImage: "eye.slash")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.guestModeEnabled },
                    set: { libraryStore.setGuestModeEnabled($0) }
                )) {
                    MineSettingsLabel("游客推荐", systemImage: "person.crop.circle.badge.questionmark")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.multiAccountExperimentEnabled },
                    set: { libraryStore.setMultiAccountExperimentEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        MineSettingsLabel("多账号分工（实验）", systemImage: "person.2.badge.gearshape")

                        Text("为播放、动态、互动和历史分配账号。关闭后统一使用主账号，已保存账号不会删除。")
                            .appTypography(.settingsSubtitle, fallback: .caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text("无痕模式下新发起的播放使用游客身份，不携带登录 Cookie 或 App 凭据，也不记录或上报观看进度；需要登录的画质和付费内容可能无法播放。已开始的视频需重新打开后生效。游客推荐只影响首页推荐：开启后按未登录状态请求，不使用账号画像；关闭后 App 端推荐会带登录状态请求。点赞、投币、收藏、关注等账号操作不受影响。")
                    .piliFont(.sm)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .nativeTopScrollEdgeEffect()
        .navigationTitle("隐私设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}
