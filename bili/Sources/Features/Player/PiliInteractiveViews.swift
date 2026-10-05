import ChunUI
import SwiftUI

struct PiliInteractiveOverlay: View {
    @ObservedObject var controller: PiliInteractiveController
    let viewModel: VideoDetailViewModel
    var body: some View {
        VStack {
            Spacer()
            if controller.choicesVisible {
                VStack(spacing: 8) {
                    if controller.isLoading { ProgressView("加载分支").tint(.white) }
                    if let error = controller.errorMessage {
                        Text(error).font(.cc.sm).foregroundStyle(.white)
                        Button("重试") { controller.retry() }.buttonStyle(.glass)
                    }
                    ForEach(controller.edge?.choices ?? []) { choice in
                        Button(choice.option ?? "继续") { controller.choose(choice) }
                            .buttonStyle(.glassProminent)
                            .tint(.cc.primary)
                            .disabled(controller.isLoading)
                    }
                }
                .padding(16)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20).padding(.bottom, 72)
            }
        }
        .allowsHitTesting(controller.choicesVisible)
        .task(id: "\(viewModel.detail.bvid)|\(viewModel.api.requestSnapshot(purpose: .playback).playbackCredentialVersion)") {
            controller.prepare(viewModel)
        }
    }
}

struct PiliInteractiveHistoryView: View {
    @ObservedObject var controller: PiliInteractiveController
    var body: some View {
        NavigationStack {
            List {
                if !controller.savedHistory.isEmpty {
                    Section { CCNeoButton("继续上次分支", variant: .primary, disabled: controller.isLoading) {
                        controller.restoreSaved(); AppHelper.shared.dismissSheet()
                    } }
                }
                Section("本次分支路径") {
                    ForEach(Array(controller.history.enumerated()), id: \.offset) { index, checkpoint in
                        Button("\(index + 1). \(checkpoint.title)") {
                            controller.revisit(checkpoint); AppHelper.shared.dismissSheet()
                        }.disabled(controller.isLoading)
                    }
                }
                if controller.history.isEmpty {
                    Text(controller.isLoading ? "正在读取互动信息" : "当前视频没有互动分支").ccText(font: .cc.base, color: .cc.mutedForeground)
                }
            }
            .navigationTitle("互动分支")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button { AppHelper.shared.dismissSheet() } label: { PikaIcon(PikaIcon.Name.close) }.accessibilityLabel("关闭")
            } }
        }
    }
}
