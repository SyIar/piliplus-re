import SwiftUI

struct DanmakuSettingsSheetContent: View {
    @ObservedObject var store: VideoDetailDanmakuSettingsRenderStore
    let summary: String
    let displayAreaBinding: Binding<DanmakuDisplayArea>
    let hidesDanmakuInPortraitBinding: Binding<Bool>
    let mergesDuplicatesBinding: Binding<Bool>
    let fontScaleBinding: Binding<Double>
    let fontWeightBinding: Binding<DanmakuFontWeightOption>
    let opacityBinding: Binding<Double>
    let toggleDanmaku: () -> Void

    var body: some View {
        Form {
            DanmakuSettingsHeaderFormSection(
                store: store,
                summary: summary,
                toggleDanmaku: toggleDanmaku
            )

            DanmakuSettingsDisplayAreaSection(displayArea: displayAreaBinding)

            DanmakuSettingsPortraitVisibilitySection(
                hidesDanmakuInPortrait: hidesDanmakuInPortraitBinding
            )

            Section {
                Toggle("合并重复弹幕", isOn: mergesDuplicatesBinding)
                    .accessibilityIdentifier("ui.danmaku.merge")
            } footer: {
                Text("每 15 秒内，相同内容和样式合并显示数量；同一用户重复发送只计一次。")
            }

            DanmakuSettingsTextSection(
                settings: store.danmakuSettings,
                fontScale: fontScaleBinding,
                fontWeight: fontWeightBinding
            )

            DanmakuSettingsOpacitySection(
                settings: store.danmakuSettings,
                opacity: opacityBinding
            )
        }
    }
}
