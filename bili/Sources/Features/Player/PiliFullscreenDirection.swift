import SwiftUI
import UIKit

nonisolated enum PiliFullscreenDirection: String, CaseIterable, Identifiable, Sendable {
    case automatic, landscapeLeft, landscapeRight
    static let key = "piliplus.player.fullscreenDirection"
    static var stored: Self { Self(rawValue: UserDefaults.standard.string(forKey: key) ?? "automatic") ?? .automatic }
    var id: String { rawValue }
    var title: String { switch self { case .automatic: "跟随设备"; case .landscapeLeft: "听筒在右"; case .landscapeRight: "听筒在左" } }
    var mask: UIInterfaceOrientationMask? {
        switch self { case .automatic: nil; case .landscapeLeft: .landscapeLeft; case .landscapeRight: .landscapeRight }
    }
}

struct PiliFullscreenDirectionPicker: View {
    @AppStorage(PiliFullscreenDirection.key) private var direction = "automatic"
    var body: some View {
        PiliSettingPicker("全屏方向", selection: $direction) {
            ForEach(PiliFullscreenDirection.allCases) { Text($0.title).tag($0.rawValue) }
        }
    }
}
