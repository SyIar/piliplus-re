import SwiftUI

struct DanmakuSettingsTextSection: View {
    @AppStorage("piliplus.danmaku.separateFullscreenFont") private var separateFullscreenFont = false
    @AppStorage("piliplus.danmaku.fullscreenFontScale") private var fullscreenFontScale = 1.0

    let settings: DanmakuSettings
    @Binding var fontScale: Double
    @Binding var fontWeight: DanmakuFontWeightOption

    var body: some View {
        Section("文字") {
            DanmakuSettingsSlider(
                title: "字体大小",
                systemImage: "textformat.size",
                value: $fontScale,
                range: 0.7...1.45,
                step: 0.05,
                valueText: "\(Int((settings.fontScale * 100).rounded()))%"
            )

            Toggle("单独设置全屏弹幕字号", isOn: $separateFullscreenFont)
            if separateFullscreenFont {
                DanmakuSettingsSlider(title: "全屏字体大小", systemImage: "textformat.size",
                    value: $fullscreenFontScale, range: 0.7...1.45, step: 0.05,
                    valueText: "\(Int((fullscreenFontScale * 100).rounded()))%")
            }
            Picker(selection: $fontWeight) {
                ForEach(DanmakuFontWeightOption.allCases) { weight in
                    Text(weight.title).tag(weight)
                }
            } label: {
                PiliLabel("字体粗细", systemImage: "bold")
            }
            .pickerStyle(.navigationLink)
        }
    }
}
