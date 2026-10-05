import Combine
import Foundation
import PiliPlaybackCore

struct PiliCastSource {
    let title: String
    let duration: Double
    let position: Double
    let variant: PlayVariant?
    let localFile: URL?
    let headers: [String: String]

    static func online(_ model: VideoDetailViewModel) throws -> Self {
        guard let variant = model.selectedPlayVariant, variant.videoURL != nil, variant.audioURL != nil else {
            throw UPnPError.soap("请先加载视频；当前投屏支持 DASH 音视频与已下载的视频")
        }
        return Self(title: model.detail.title, duration: model.stablePlayerViewModel?.duration ?? 0,
                    position: model.stablePlayerViewModel?.currentTime ?? 0, variant: variant, localFile: nil,
                    headers: BiliHLSManifestBuilder.httpHeaders(referer: "https://www.bilibili.com/video/\(model.detail.bvid)",
                                                                cookieHeader: model.api.requestSnapshot(purpose: .playback).cookieHeader))
    }
    static func offline(_ model: PiliOfflinePlaybackModel) throws -> Self {
        Self(title: model.item.title, duration: model.item.duration, position: model.player.currentTime,
             variant: nil, localFile: try PiliOfflineStorage.playbackURL(model.item), headers: [:])
    }
}

@MainActor
final class PiliDLNAController: ObservableObject {
    static let shared = PiliDLNAController()
    @Published private(set) var renderer: UPnPRenderer?
    @Published private(set) var title = ""
    @Published private(set) var isBusy = false
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var volume: Double = 50
    @Published private(set) var errorMessage: String?
    private let client = PiliDLNAClient()
    private var host: PiliCastingMediaHost?
    private var operationTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var generation = UUID()
    private var hasPlayed = false
    private var didReachEnd = false
    private var timerStopRequested = false

    var hasActiveItem: Bool { renderer != nil || isBusy }

    func start(_ source: PiliCastSource, on device: UPnPRenderer) {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil; timerStopRequested = false
        PiliSleepTimer.shared.resumeManually()
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isBusy = false }
            var newHost: PiliCastingMediaHost?
            do {
                if self.renderer != nil { try await self.stopCurrent() }
                let token = UUID(); self.generation = token
                let address = try PiliLANAddress.currentIPv4()
                guard let target = device.location.host else { throw UPnPError.invalidDescription }
                if let file = source.localFile {
                    newHost = try await PiliCastingMediaHost.offline(file: file, address: address, renderer: target)
                } else if let variant = source.variant {
                    newHost = try await LocalHLSBridge.makeCasting(variant: variant, duration: source.duration > 0 ? source.duration : nil,
                                                                  headers: source.headers, address: address, renderer: target)
                }
                try Task.checkCancellation()
                guard let prepared = newHost, !self.timerStopRequested else { throw CancellationError() }
                self.renderer = device; self.host = prepared; self.title = source.title
                self.duration = source.duration; self.position = 0; self.hasPlayed = false; self.didReachEnd = false
                try await self.client.command("SetAVTransportURI", service: device.transport, arguments: [
                    ("CurrentURI", prepared.url.absoluteString),
                    ("CurrentURIMetaData", UPnPSOAP.metadata(url: prepared.url, title: source.title, mime: prepared.mimeType))
                ])
                try Task.checkCancellation()
                try await self.client.command("Play", service: device.transport, arguments: [("Speed", "1")])
                try Task.checkCancellation()
                self.isPlaying = true
                ActivePlaybackCoordinator.shared.currentActivePlayer()?.pause()
                if source.position > 1 {
                    do {
                        try await self.client.command("Seek", service: device.transport,
                                                       arguments: [("Unit", "REL_TIME"), ("Target", UPnPSOAP.timestamp(source.position))])
                    } catch { if !Task.isCancelled { self.errorMessage = "已开始投屏，但设备未接受跳转：\(error.localizedDescription)" } }
                }
                try Task.checkCancellation()
                self.startPolling(token: token)
            } catch {
                if self.renderer == nil { newHost?.stop() }
                if !Task.isCancelled { self.errorMessage = error.localizedDescription }
                // Keep a possibly started device visible so the user can retry Stop.
            }
        }
    }
    func playPause() {
        guard let renderer else { return }
        let play = !isPlaying
        if play { PiliSleepTimer.shared.resumeManually() }
        perform {
            try await self.client.command(play ? "Play" : "Pause", service: renderer.transport,
                                           arguments: play ? [("Speed", "1")] : [])
            self.isPlaying = play
        }
    }
    func seek(_ time: Double) {
        guard let renderer else { return }
        perform {
            try await self.client.command("Seek", service: renderer.transport,
                                           arguments: [("Unit", "REL_TIME"), ("Target", UPnPSOAP.timestamp(time))])
            self.position = time; self.didReachEnd = false
        }
    }
    func setVolume(_ value: Double) {
        guard let service = renderer?.rendering else { return }
        let clamped = min(100, max(0, value))
        perform {
            try await self.client.command("SetVolume", service: service,
                                           arguments: [("Channel", "Master"), ("DesiredVolume", String(Int(clamped)))])
            self.volume = clamped
        }
    }
    func stop() { perform { try await self.stopCurrent() } }
    func stopForTimer() {
        guard hasActiveItem, !timerStopRequested else { return }
        timerStopRequested = true
        let pending = operationTask
        pending?.cancel()
        Task { [weak self] in
            await pending?.value
            guard let self else { return }
            self.perform {
                do { try await self.stopCurrent() }
                catch { throw UPnPError.soap("定时停止未获设备确认，请重试停止：\(error.localizedDescription)") }
            }
        }
    }
    private func stopCurrent() async throws {
        pollingTask?.cancel(); pollingTask = nil
        generation = UUID()
        guard let renderer else { host?.stop(); host = nil; return }
        do { try await client.command("Stop", service: renderer.transport) }
        catch {
            // Stop serving media even if the TV cannot be contacted. Its buffered tail may still play.
            host?.stop(); host = nil
            throw error
        }
        host?.stop(); host = nil; self.renderer = nil
        isPlaying = false; position = 0; title = ""; timerStopRequested = false
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil
        operationTask = Task { [weak self] in
            defer { self?.isBusy = false }
            do { try await action() }
            catch { self?.errorMessage = error.localizedDescription }
        }
    }
    private func startPolling(token: UUID) {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let device = self.renderer, self.generation == token else { return }
                if !self.isBusy {
                    do {
                        let time = try await self.client.command("GetPositionInfo", service: device.transport)
                        let transport = try await self.client.command("GetTransportInfo", service: device.transport)
                        guard !Task.isCancelled, self.generation == token, !self.isBusy else { continue }
                        if let value = UPnPSOAP.seconds(time["RelTime"]) { self.position = value }
                        if let value = UPnPSOAP.seconds(time["TrackDuration"]), value > 0 { self.duration = value }
                        let state = transport["CurrentTransportState"] ?? ""
                        self.isPlaying = state == "PLAYING" || state == "TRANSITIONING"
                        if state == "PLAYING" { self.hasPlayed = true }
                        if state == "STOPPED", self.hasPlayed, !self.didReachEnd,
                           self.duration > 0, self.position >= self.duration - 3 {
                            self.didReachEnd = true
                            if PiliSleepTimer.shared.shouldStopAtPlaybackEnd() { self.stopForTimer() }
                        }
                    } catch {
                        guard !Task.isCancelled, self.generation == token else { return }
                        self.errorMessage = "暂时无法读取投屏状态：\(error.localizedDescription)"
                    }
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
