import AVFoundation
import SwiftUI

nonisolated enum PiliVideoAspect: String, CaseIterable, Identifiable, Sendable {
    case fit, fill, stretch, width, height
    static let key = "piliplus.player.aspect"
    static var stored: Self { Self(rawValue: UserDefaults.standard.string(forKey: key) ?? "fit") ?? .fit }
    var id: String { rawValue }
    var title: String {
        switch self { case .fit: "完整显示"; case .fill: "填满裁切"; case .stretch: "拉伸铺满"; case .width: "适应宽度"; case .height: "适应高度" }
    }
    var gravity: AVLayerVideoGravity {
        switch self { case .fill: .resizeAspectFill; case .stretch: .resize; default: .resizeAspect }
    }
    func frame(in bounds: CGRect, videoSize: CGSize) -> CGRect {
        guard bounds.width > 0, bounds.height > 0, videoSize.width.isFinite, videoSize.height.isFinite,
              videoSize.width > 0, videoSize.height > 0 else { return bounds }
        let aspect = videoSize.width / videoSize.height
        let size: CGSize
        switch self {
        case .width: size = .init(width: bounds.width, height: bounds.width / aspect)
        case .height: size = .init(width: bounds.height * aspect, height: bounds.height)
        default: return bounds
        }
        return .init(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
}

private struct PiliVideoAspectBinding: ViewModifier {
    let player: PlayerStateViewModel
    @AppStorage(PiliVideoAspect.key) private var mode = "fit"
    func body(content: Content) -> some View {
        content.onChange(of: mode, initial: true) { _, value in
            player.setVideoGravity((PiliVideoAspect(rawValue: value) ?? .fit).gravity)
            player.refreshSurfaceLayout()
        }
    }
}
extension View { func piliVideoAspect(player: PlayerStateViewModel) -> some View { modifier(PiliVideoAspectBinding(player: player)) } }

struct PiliVideoAspectPicker: View {
    @AppStorage(PiliVideoAspect.key) private var mode = "fit"
    var body: some View {
        Picker("画面比例", selection: $mode) { ForEach(PiliVideoAspect.allCases) { Text($0.title).tag($0.rawValue) } }
    }
}
