import ChunUI
import SwiftUI

struct PiliInteractiveOverlay: View {
    @ObservedObject var controller: PiliInteractiveController
    @Environment(\.scenePhase) private var scenePhase
    let viewModel: VideoDetailViewModel
    var body: some View {
        PiliInteractiveChoicesView(controller: controller)
            .task(id: "\(viewModel.detail.bvid)|\(viewModel.api.requestSnapshot(purpose: .playback).playbackCredentialVersion)") {
                controller.prepare(viewModel)
                controller.setPresentationActive(scenePhase == .active)
                while !Task.isCancelled {
                    if let player = viewModel.stablePlayerViewModel {
                        controller.updatePlayback(time: player.playbackClock.currentTime, duration: player.playbackClock.duration ?? 0)
                    }
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { break }
                }
            }
            .onChange(of: scenePhase) { _, phase in controller.setPresentationActive(phase == .active) }
            .onDisappear { controller.setPresentationActive(false) }
    }
}

struct PiliInteractiveChoicesView: View {
    @ObservedObject var controller: PiliInteractiveController
    @State private var listsHotspots = false
    var body: some View {
        GeometryReader { geometry in
            if controller.isOverlayVisible {
                ZStack {
                    if usesHotspots {
                        hotspotButtons(in: geometry.size)
                    }
                    VStack(spacing: 10) {
                        HStack {
                            if let remaining = controller.remainingSeconds {
                                Label("\(Int(ceil(remaining))) 秒", systemImage: "timer")
                                    .monospacedDigit().accessibilityIdentifier("ui.interactive.countdown")
                            }
                            Spacer()
                            if controller.plan?.question.type == 2 && !controller.visibleChoices.isEmpty {
                                Button(listsHotspots ? "画面选择" : "列表选择") { listsHotspots.toggle() }
                                    .buttonStyle(.glass)
                            }
                        }.font(.caption.weight(.semibold))
                        Spacer(minLength: 0)
                        if controller.isLoading {
                            ProgressView("加载分支").tint(.white)
                        } else if let error = controller.errorMessage {
                            Text(error).font(.caption).multilineTextAlignment(.center)
                            Button("重试") { controller.retry() }.buttonStyle(.glass)
                        }
                        if !controller.isLoading && !usesHotspots && !controller.visibleChoices.isEmpty {
                            ScrollView {
                                VStack(spacing: 8) {
                                    if let title = controller.plan?.question.title, !title.isEmpty {
                                        Text(title).font(.headline)
                                    }
                                    ForEach(controller.visibleChoices) { choice in choiceButton(choice) }
                                }
                            }
                            .frame(maxHeight: min(240, max(100, geometry.size.height - 110)))
                        }
                        if !controller.isLoading && controller.errorMessage == nil
                            && controller.hasEnded && controller.plan == nil {
                            Text("剧情已结束").font(.headline).accessibilityIdentifier("ui.interactive.finished")
                            Button("重新开始") { controller.restart() }.buttonStyle(.glassProminent).tint(.cc.primary)
                        }
                        if !shownVariables.isEmpty {
                            Text(shownVariables).font(.caption).foregroundStyle(.white.opacity(0.85))
                                .accessibilityIdentifier("ui.interactive.variables")
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 52).padding(.bottom, geometry.size.height > 250 ? 76 : 16)
                    .background(alignment: .bottom) {
                        LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                            .allowsHitTesting(false)
                    }
                }
                .foregroundStyle(.white)
                .accessibilityIdentifier("ui.interactive.overlay")
            }
        }
        .allowsHitTesting(controller.isOverlayVisible)
        .onChange(of: controller.history.last?.id) { _, _ in listsHotspots = false }
    }
    private var shownVariables: String {
        controller.session.metadata.values.filter(\.isShow).sorted { $0.key < $1.key }.prefix(6).map {
            let value = controller.session.values[$0.key] ?? 0
            return "\($0.name ?? "进度")：\(value.formatted(.number.precision(.fractionLength(0...2))))"
        }.joined(separator: "  ·  ")
    }
    private var sourceSize: CGSize? {
        guard let dimension = controller.edge?.edges?.dimension,
              dimension.rotate == nil || dimension.rotate == 0,
              let width = dimension.width, let height = dimension.height,
              width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }
    private var usesHotspots: Bool {
        guard !listsHotspots, !controller.isLoading, controller.errorMessage == nil,
              controller.plan?.question.type == 2, let size = sourceSize,
              !controller.visibleChoices.isEmpty else { return false }
        return controller.visibleChoices.allSatisfy { $0.normalizedHotspot(width: size.width, height: size.height) != nil }
    }
    @ViewBuilder
    private func hotspotButtons(in size: CGSize) -> some View {
        if let sourceSize, size.width > 0, size.height > 0 {
            let scale = min(size.width / sourceSize.width, size.height / sourceSize.height)
            let video = CGRect(x: (size.width - sourceSize.width * scale) / 2,
                               y: (size.height - sourceSize.height * scale) / 2,
                               width: sourceSize.width * scale, height: sourceSize.height * scale)
            ForEach(controller.visibleChoices) { choice in
                if let point = choice.normalizedHotspot(width: sourceSize.width, height: sourceSize.height) {
                    let width = min(150.0, video.width)
                    let anchor = video.minX + point.x * video.width
                    let x = choice.textAlign == 1 ? anchor + width / 2 : choice.textAlign == 3 ? anchor - width / 2 : anchor
                    choiceButton(choice)
                        .frame(width: width, height: 48)
                        .position(x: min(max(x, video.minX + width / 2), video.maxX - width / 2),
                                  y: min(max(video.minY + point.y * video.height, video.minY + 24), max(video.minY + 24, video.maxY - 24)))
                }
            }
        }
    }
    private func choiceButton(_ choice: PiliInteractiveEdge.Choice) -> some View {
        Button { controller.choose(choice) } label: {
            Text(choice.option?.isEmpty == false ? choice.option! : "继续")
                .font(.callout.weight(.semibold)).lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.glassProminent).tint(.cc.primary)
        .disabled(controller.isLoading)
        .accessibilityIdentifier("ui.interactive.choice.\(choice.id)")
    }
}

struct PiliInteractiveHistoryView: View {
    @ObservedObject var controller: PiliInteractiveController
    var body: some View {
        NavigationStack {
            List {
                if controller.isBacktrackingRestricted {
                    Label("作者已限制本段剧情回溯", systemImage: "lock")
                }
                if !controller.savedHistory.isEmpty {
                    Section {
                        CCNeoButton("继续上次分支", variant: .primary, disabled: controller.isLoading || controller.isBacktrackingRestricted) {
                            controller.restoreSaved(); AppHelper.shared.dismissSheet()
                        }
                    }
                }
                Section("本次分支路径") {
                    ForEach(Array(controller.history.enumerated()), id: \.element.id) { index, checkpoint in
                        Button("\(index + 1). \(checkpoint.title)") {
                            controller.revisit(checkpoint); AppHelper.shared.dismissSheet()
                        }.disabled(controller.isLoading || controller.isBacktrackingRestricted)
                    }
                }
                if controller.history.isEmpty {
                    Text(controller.isLoading ? "正在读取互动信息" : "当前视频没有互动分支").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("互动分支").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button { AppHelper.shared.dismissSheet() } label: { PikaIcon(PikaIcon.Name.close) }.accessibilityLabel("关闭")
            } }
        }
    }
}
