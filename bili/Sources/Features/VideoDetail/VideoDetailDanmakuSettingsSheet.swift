import SwiftUI

struct DanmakuSettingsSheet: View {
    @ObservedObject var store: VideoDetailDanmakuSettingsRenderStore
    let toggleDanmaku: () -> Void
    let updateDanmakuSettings: (DanmakuSettings) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DanmakuSettingsSheetContent(
                store: store,
                summary: settingsSummary,
                displayAreaBinding: displayAreaBinding,
                hidesDanmakuInPortraitBinding: hidesDanmakuInPortraitBinding,
                mergesDuplicatesBinding: mergesDuplicatesBinding,
                fontScaleBinding: fontScaleBinding,
                fontWeightBinding: fontWeightBinding,
                opacityBinding: opacityBinding,
                toggleDanmaku: toggleDanmaku,
                updateExtendedSettings: updateDanmakuSettings
            )
            .navigationTitle("弹幕设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                VideoDetailDoneToolbar(
                    finish: dismissDanmakuSettings,
                    accessibilityIdentifier: "ui.videoDetail.sheet.danmakuSettings.done"
                )
            }
        }
        .accessibilityIdentifier("ui.videoDetail.sheet.danmakuSettings")
    }

    private func dismissDanmakuSettings() {
        dismiss()
    }
}
