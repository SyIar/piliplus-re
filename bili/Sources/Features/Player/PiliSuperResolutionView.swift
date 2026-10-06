import AVFoundation
import CoreImage
import MetalKit
import SwiftUI
import ChunUI
#if canImport(MetalFX)
import MetalFX
#endif

nonisolated enum PiliSuperResolutionPolicy {
    static let key = "piliplus.player.superResolution"
    static let changed = Notification.Name("PiliSuperResolutionChanged")
    static func outputSize(width: Int, height: Int, target: CGSize, mode: Int) -> CGSize? {
        guard width > 0, height > 0, width <= 1920, height <= 1920, mode > 0,
              target.width.isFinite, target.height.isFinite, target.width > 0, target.height > 0 else { return nil }
        let limit = mode == 1 ? 1.5 : 2.0
        let scale = min(limit, target.width / Double(width), target.height / Double(height), 2560 / Double(max(width, height)))
        guard scale > 1.05 else { return nil }
        return CGSize(width: (Double(width) * scale).rounded(.down), height: (Double(height) * scale).rounded(.down))
    }
}

struct PiliSuperResolutionSettingsView: View {
    @AppStorage(PiliSuperResolutionPolicy.key) private var mode = 0
    private var supported: Bool {
#if canImport(MetalFX)
        MTLCreateSystemDefaultDevice().map { MTLFXSpatialScalerDescriptor.supportsDevice($0) } ?? false
#else
        false
#endif
    }
    var body: some View {
        PiliForm {
            Picker("超分辨率", selection: $mode) { Text("关闭").tag(0); Text("效率 · 最高 1.5 倍").tag(1); Text("画质 · 最高 2 倍").tag(2) }
                .disabled(!supported)
            Text(supported ? "使用 MetalFX 空间超分放大低分辨率画面。只在放大 SDR 视频时运行；HDR、画中画、低电量模式和设备发热时使用原始画面。" : "当前设备不支持 MetalFX 空间超分。")
                .piliFont(.sm).foregroundStyle(.secondary)
            Text("开启会增加 GPU 耗电。效率模式限制放大倍率和刷新率，画质模式适合性能充足的设备。")
                .piliFont(.sm).foregroundStyle(.secondary)
        }.navigationTitle("超分辨率")
            .onChange(of: mode) { _, _ in NotificationCenter.default.post(name: PiliSuperResolutionPolicy.changed, object: nil) }
    }
}

/// The native AVPlayer remains underneath and continues to own audio, timing and PiP.
/// Only SDR display frames are upscaled, with two GPU jobs at most and no CPU pixel copies.
#if canImport(MetalFX)
@MainActor
final class PiliSuperResolutionView: MTKView, MTKViewDelegate {
    private weak var player: AVPlayer?
    private weak var item: AVPlayerItem?
    private let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferMetalCompatibilityKey as String: true])
    private let commandQueue: MTLCommandQueue
    private let imageContext: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private var textureCache: CVMetalTextureCache?
    private var scaler: (any MTLFXSpatialScaler)?
    private var targetTexture: (any MTLTexture)?
    private var dimensions = [Int]()
    private let inFlight = DispatchSemaphore(value: 2)
    private let mode: Int
    private var stopped = false

    init?(player: AVPlayer, item: AVPlayerItem, mode: Int) {
        guard let device = MTLCreateSystemDefaultDevice(), MTLFXSpatialScalerDescriptor.supportsDevice(device),
              let queue = device.makeCommandQueue() else { return nil }
        self.player = player; self.item = item; self.mode = mode; commandQueue = queue
        imageContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        super.init(frame: .zero, device: device)
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache) == kCVReturnSuccess else { return nil }
        output.suppressesPlayerRendering = false; item.add(output)
        delegate = self; framebufferOnly = false; colorPixelFormat = .bgra8Unorm
        backgroundColor = .clear; isOpaque = false; isUserInteractionEnabled = false
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        preferredFramesPerSecond = mode == 1 ? 30 : 60
        enableSetNeedsDisplay = false; isPaused = false
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func isUsing(_ item: AVPlayerItem) -> Bool { self.item === item && !stopped }
    func invalidateFrame() { alpha = 0 }
    func stop() {
        stopped = true; isPaused = true; delegate = nil; item?.remove(output)
        removeFromSuperview(); scaler = nil; targetTexture = nil
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { dimensions = [] }
    func draw(in view: MTKView) {
        guard !stopped, window != nil, let player, player.currentItem === item,
              UIApplication.shared.applicationState == .active, !ProcessInfo.processInfo.isLowPowerModeEnabled,
              ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue else { alpha = 0; return }
        preferredFramesPerSecond = player.rate == 0 ? 5 : (mode == 1 ? 30 : 60)
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time), inFlight.wait(timeout: .now()) == .success else { return }
        var submitted = false
        defer { if !submitted { inFlight.signal() } }
        guard let pixels = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil),
              let textureCache, let device else { return }
        let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
        guard let size = PiliSuperResolutionPolicy.outputSize(width: width, height: height, target: drawableSize, mode: mode),
              abs(Double(width) / Double(height) - bounds.width / max(1, bounds.height)) < 0.1 else { alpha = 0; return }
        let next = [width, height, Int(size.width), Int(size.height)]
        if dimensions != next {
            let descriptor = MTLFXSpatialScalerDescriptor()
            descriptor.inputWidth = width; descriptor.inputHeight = height
            descriptor.outputWidth = next[2]; descriptor.outputHeight = next[3]
            descriptor.colorTextureFormat = .bgra8Unorm; descriptor.outputTextureFormat = .bgra8Unorm
            descriptor.colorProcessingMode = .perceptual
            scaler = descriptor.makeSpatialScaler(device: device)
            let texture = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: next[2], height: next[3], mipmapped: false)
            texture.usage = [.shaderRead, .shaderWrite, .renderTarget]; texture.storageMode = .private
            targetTexture = device.makeTexture(descriptor: texture); dimensions = next
        }
        var reference: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixels, nil, .bgra8Unorm, width, height, 0, &reference) == kCVReturnSuccess,
              let reference, let input = CVMetalTextureGetTexture(reference), let scaler, let targetTexture,
              let buffer = commandQueue.makeCommandBuffer(), let drawable = currentDrawable else { alpha = 0; return }
        scaler.colorTexture = input; scaler.outputTexture = targetTexture
        scaler.inputContentWidth = width; scaler.inputContentHeight = height
        scaler.encode(commandBuffer: buffer)
        guard let image = CIImage(mtlTexture: targetTexture, options: [.colorSpace: colorSpace]) else { return }
        let display = image.transformed(by: CGAffineTransform(scaleX: Double(drawable.texture.width) / Double(next[2]), y: Double(drawable.texture.height) / Double(next[3])))
        imageContext.render(display, to: drawable.texture, commandBuffer: buffer,
            bounds: CGRect(x: 0, y: 0, width: drawable.texture.width, height: drawable.texture.height), colorSpace: colorSpace)
        buffer.present(drawable)
        let semaphore = inFlight
        let lifetime = PiliMetalFrameLifetime(texture: reference, pixels: pixels)
        buffer.addCompletedHandler { [weak self, lifetime] command in
            _ = withExtendedLifetime(lifetime) { semaphore.signal() }
            let success = command.status == .completed
            Task { @MainActor [weak self] in guard let self, !self.stopped else { return }; self.alpha = success ? 1 : 0 }
        }
        submitted = true; buffer.commit()
    }
}

/// Immutable retention only; AVFoundation/CoreVideo own synchronization of the buffers.
nonisolated private final class PiliMetalFrameLifetime: @unchecked Sendable {
    let texture: CVMetalTexture
    let pixels: CVPixelBuffer
    init(texture: CVMetalTexture, pixels: CVPixelBuffer) { self.texture = texture; self.pixels = pixels }
}
#else
@MainActor
final class PiliSuperResolutionView: UIView {
    init?(player: AVPlayer, item: AVPlayerItem, mode: Int) { return nil }
    required init?(coder: NSCoder) { return nil }
    func isUsing(_ item: AVPlayerItem) -> Bool { false }
    func invalidateFrame() {}
    func stop() { removeFromSuperview() }
}
#endif
