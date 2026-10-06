import ChunUI
import PiliPlaybackCore
import SwiftUI

struct PiliPlaybackToolsView: View {
    @ObservedObject private var sleepTimer = PiliSleepTimer.shared
    @ObservedObject private var preferences = PiliPlaybackPreferences.shared
    @State private var minutes = 30
    @State private var finishCurrent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("播放方式").ccText(font: .cc.lgBold, color: .cc.foreground)
                    Spacer()
                    Button { AppHelper.shared.dismissSheet() } label: {
                        PikaIcon(PikaIcon.Name.close, size: 20)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("关闭播放设置")
                }

                PiliVideoAspectPicker()
                VStack(alignment: .leading, spacing: 12) {
                    Text("自动连播").ccText(font: .cc.baseBold, color: .cc.foreground)
                    Picker("播放顺序", selection: Binding(get: { preferences.order }, set: { preferences.setOrder($0) })) {
                        ForEach(PlaybackOrder.allCases, id: \.rawValue) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.cc.primary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("定时停止").ccText(font: .cc.baseBold, color: .cc.foreground)
                    Text(sleepTimer.summary).ccText(font: .cc.sm, color: .cc.mutedForeground)
                    Stepper("\(minutes) 分钟", value: $minutes, in: 5...180, step: 5)
                        .font(.cc.base)
                    Toggle("到点后播完当前视频", isOn: $finishCurrent)
                        .font(.cc.base)
                        .tint(.cc.primary)
                    CCNeoButton("开始计时", icon: "timer-default", fullWidth: true) {
                        sleepTimer.schedule(minutes: minutes, finishCurrent: finishCurrent)
                        CCToastCenter.shared.show(.success, "已设置定时停止")
                    }
                    CCNeoButton("播完当前视频后停止", variant: .secondary, fullWidth: true) {
                        sleepTimer.stopAfterCurrent()
                    }
                    if sleepTimer.policy.state != .off {
                        CCNeoButton("取消定时", variant: .ghost, fullWidth: true) { sleepTimer.cancel() }
                    }
                }
                Text("定时停止优先于自动连播和循环播放。")
                    .ccText(font: .cc.sm, color: .cc.mutedForeground)
            }
            .padding(24)
        }
        .background(Color.cc.background)
    }

    static func present() {
        AppHelper.shared.presentSheet(.half) { PiliPlaybackToolsView() }
    }
}

extension PlaybackOrder {
    var systemImage: String {
        switch self {
        case .stop: "stop.circle"
        case .repeatOne: "repeat.1"
        case .sequential: "list.number"
        case .repeatList: "repeat"
        case .related: "play.rectangle.on.rectangle"
        }
    }
    var subtitle: String {
        switch self {
        case .stop: "当前内容结束后暂停"
        case .repeatOne: "循环播放当前分 P 或单集"
        case .sequential: "按当前列表继续，末尾停止"
        case .repeatList: "按当前列表继续，末尾回到开头"
        case .related: "当前内容结束后继续相关推荐；明确选择的列表仍按列表顺序播放"
        }
    }

    var title: String {
        switch self {
        case .stop: "播完暂停"
        case .repeatOne: "单个循环"
        case .sequential: "顺序播放"
        case .repeatList: "列表循环"
        case .related: "自动连播相关视频"
        }
    }
}
