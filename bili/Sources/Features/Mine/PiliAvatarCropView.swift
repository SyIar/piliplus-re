import ChunUI
import SwiftUI
import UIKit

struct PiliAvatarCropView: View {
    let api: BiliAPIClient
    let identity: PiliAccountIdentity
    let image: UIImage
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var previousScale: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var previousOffset = CGSize.zero
    @State private var busy = false
    @State private var errorMessage: String?
    private let side: CGFloat = 240
    private var fittedSize: CGSize {
        let factor = max(side / image.size.width, side / image.size.height)
        return CGSize(width: image.size.width * factor, height: image.size.height * factor)
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("拖动、缩放照片以调整头像").ccText(font: .cc.base, color: .cc.mutedForeground)
                Image(uiImage: image).resizable()
                    .frame(width: fittedSize.width * scale, height: fittedSize.height * scale)
                    .offset(offset)
                    .frame(width: side, height: side).clipped()
                    .overlay { Circle().stroke(.white, lineWidth: 2).padding(1).allowsHitTesting(false) }
                    .contentShape(Rectangle())
                    .gesture(DragGesture().onChanged { value in
                        offset = bounded(CGSize(width: previousOffset.width + value.translation.width,
                                                height: previousOffset.height + value.translation.height))
                    }.onEnded { _ in previousOffset = offset })
                    .simultaneousGesture(MagnifyGesture().onChanged { value in
                        scale = min(max(previousScale * value.magnification, 1), 8)
                        offset = bounded(offset)
                    }.onEnded { _ in previousScale = scale; previousOffset = offset })
                    .accessibilityLabel("头像裁剪区域")
                VStack {
                    Slider(value: $scale, in: 1...8, onEditingChanged: { editing in
                        if !editing { previousScale = scale; previousOffset = offset }
                    }).accessibilityLabel("头像缩放")
                        .onChange(of: scale) { _, _ in offset = bounded(offset) }
                    Button("重置位置") { scale = 1; previousScale = 1; offset = .zero; previousOffset = .zero }
                }.frame(maxWidth: 280)
                if let errorMessage { Text(errorMessage).foregroundStyle(Color.cc.destructive) }
                if busy { ProgressView("上传头像") }
            }.frame(maxWidth: .infinity).padding(24)
        }
        .disabled(busy)
        .navigationTitle("裁剪头像")
        .interactiveDismissDisabled(busy)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
            ToolbarItem(placement: .confirmationAction) { Button("保存头像") { save() }.disabled(busy) }
        }
    }
    private func bounded(_ value: CGSize) -> CGSize {
        let x = max(0, (fittedSize.width * scale - side) / 2)
        let y = max(0, (fittedSize.height * scale - side) / 2)
        return CGSize(width: min(max(value.width, -x), x), height: min(max(value.height, -y), y))
    }
    private func save() {
        guard !busy else { return }
        let outputSide: CGFloat = 640
        let factor = outputSide / side
        let constrained = bounded(offset)
        let target = CGSize(width: fittedSize.width * scale * factor, height: fittedSize.height * scale * factor)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let jpeg = UIGraphicsImageRenderer(size: CGSize(width: outputSide, height: outputSide), format: format).jpegData(withCompressionQuality: 0.9) { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: outputSide, height: outputSide))
            image.draw(in: CGRect(x: (outputSide - target.width) / 2 + constrained.width * factor,
                                  y: (outputSide - target.height) / 2 + constrained.height * factor,
                                  width: target.width, height: target.height))
        }
        busy = true; errorMessage = nil
        Task {
            defer { busy = false }
            do { try await api.updatePiliAvatar(jpeg: jpeg, identity: identity); onSaved(); dismiss() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
