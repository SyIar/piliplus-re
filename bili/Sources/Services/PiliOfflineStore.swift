import Combine
import Foundation
import PiliPlaybackCore
import UIKit

@MainActor
final class PiliOfflineStore: ObservableObject {
    static let shared = PiliOfflineStore()
    static let sessionIdentifier = "io.github.syiar.PiliPlusSwift.offline.v1"
    @Published private(set) var items: [OfflineDownloadItem] = []
    @Published private(set) var storageError: String?
    private var api: BiliAPIClient?
    private let delegate = PiliOfflineSessionDelegate()
    private var transfers: [OfflineTaskIdentity: URLSessionDownloadTask] = [:]
    private var preparing: [UUID: Task<Void, Never>] = [:]
    private var finalizing: [UUID: Task<Void, Never>] = [:]
    private var extras: [UUID: Task<Void, Never>] = [:]
    private var lastProgressUpdate: [OfflineTaskIdentity: Date] = [:]
    private var restoring = true
    private var restoredUnclaimedItems = Set<UUID>()
    private var indexLoadFailed = false
    private var backgroundCompletion: (() -> Void)?
    private var backgroundEventsFinished = false
    private var foregroundObserver: AnyCancellable?
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 2
        config.timeoutIntervalForResource = 7 * 24 * 60 * 60
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: config, delegate: delegate, delegateQueue: queue)
    }()

    private init() {
        do { items = try PiliOfflineStorage.load() }
        catch { storageError = "下载索引读取失败：\(error.localizedDescription)"; indexLoadFailed = true }
        foregroundObserver = NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.pump() } }
        session.getAllTasks { [weak self] tasks in
            DispatchQueue.main.async { self?.restore(tasks) }
        }
    }

    func configure(api: BiliAPIClient) { self.api = api; pump() }

    func handleBackgroundEvents(completion: @escaping () -> Void) {
        backgroundCompletion = completion
        backgroundEventsFinished = false
        _ = session
    }

    func finishedBackgroundEvents() {
        // A completed OS transfer may no longer appear in getAllTasks. Keep any delivered
        // part, but do not leave the queue blocked if its other transfer disappeared.
        for index in items.indices where items[index].state == .downloading {
            let id = items[index].id
            if !items[index].isReadyToFinalize && !transfers.keys.contains(where: { $0.itemID == id }) {
                items[index].state = .paused
                items[index].errorMessage = "后台传输已中断，点击继续"
            }
        }
        persist()
        pump()
        backgroundEventsFinished = true
        completeBackgroundEventsIfReady()
    }

    private func completeBackgroundEventsIfReady() {
        guard backgroundEventsFinished, finalizing.isEmpty, preparing.isEmpty, let completion = backgroundCompletion else { return }
        backgroundCompletion = nil
        backgroundEventsFinished = false
        completion()
    }

    func enqueue(video: VideoItem, pages: [VideoPage], variant: PlayVariant) throws -> Int {
        guard !indexLoadFailed else { throw PiliOfflineError.message(storageError ?? "下载索引无法读取") }
        guard variant.isPlayable else { throw PiliOfflineError.message("当前画质不可下载") }
        var updated = items
        var added = 0
        for page in pages where page.cid > 0 {
            guard !updated.contains(where: { $0.bvid == video.bvid && $0.cid == page.cid
                && $0.effectiveMediaKind == .video && $0.quality == variant.quality }) else { continue }
            let title = pages.count > 1 || (video.pages?.count ?? 0) > 1
                ? "\(video.title) · \(page.part ?? "P\(page.page ?? 1)")" : video.title
            let item = OfflineDownloadItem(
                bvid: video.bvid, cid: page.cid, title: title, author: video.owner?.name ?? "",
                coverURL: video.pic, duration: Double(page.duration ?? video.duration ?? 0),
                quality: variant.quality, qualityTitle: variant.title, codec: variant.codec,
                seasonID: video.pgcSeasonID, episodeID: video.pgcEpisodeID
            )
            updated.append(item)
            added += 1
        }
        try PiliOfflineStorage.save(updated)
        items = updated
        pump()
        return added
    }

    func enqueueAudio(video: VideoItem, pages: [VideoPage], audio: VideoListenAudioVariant) throws -> Int {
        guard !indexLoadFailed else { throw PiliOfflineError.message(storageError ?? "下载索引无法读取") }
        var updated = items
        var added = 0
        for page in pages where page.cid > 0 {
            guard !updated.contains(where: { $0.bvid == video.bvid && $0.cid == page.cid
                && $0.effectiveMediaKind == .audio && $0.audioQualityID == audio.stream.id }) else { continue }
            var item = OfflineDownloadItem(
                bvid: video.bvid, cid: page.cid,
                title: (video.pages?.count ?? pages.count) > 1 ? "\(video.title) · \(page.part ?? "P\(page.page ?? 1)")" : video.title,
                author: video.owner?.name ?? "", coverURL: video.pic,
                duration: Double(page.duration ?? video.duration ?? 0), quality: 0,
                qualityTitle: "仅音频 · \(audio.title)", codec: audio.stream.codecs,
                seasonID: video.pgcSeasonID, episodeID: video.pgcEpisodeID
            )
            item.mediaKind = .audio
            item.audioQualityID = audio.stream.id
            updated.append(item)
            added += 1
        }
        try PiliOfflineStorage.save(updated)
        items = updated
        pump()
        return added
    }

    func pause(_ id: UUID) {
        guard let index = index(id), [.queued, .preparing, .downloading, .finalizing].contains(items[index].state) else { return }
        items[index].state = .paused
        preparing.removeValue(forKey: id)?.cancel()
        finalizing[id]?.cancel()
        extras.removeValue(forKey: id)?.cancel()
        cancelTransfers(for: id, saveResumeData: true)
        persist(); pump()
    }

    func resume(_ id: UUID) {
        guard let index = index(id), [.paused, .failed].contains(items[index].state) else { return }
        items[index].state = .queued
        restoredUnclaimedItems.remove(id)
        items[index].errorMessage = nil
        persist(); pump()
    }

    func remove(_ id: UUID) {
        restoredUnclaimedItems.remove(id)
        preparing.removeValue(forKey: id)?.cancel()
        finalizing[id]?.cancel()
        extras.removeValue(forKey: id)?.cancel()
        cancelTransfers(for: id, saveResumeData: false)
        items.removeAll { $0.id == id }
        if let directory = try? PiliOfflineStorage.directory(id) { try? FileManager.default.removeItem(at: directory) }
        persist(); pump()
    }

    func savePlaybackPosition(_ id: UUID, time: Double) {
        guard time.isFinite, let index = index(id) else { return }
        items[index].lastPlaybackTime = max(0, time)
        persist()
    }

    func receivedProgress(_ identity: OfflineTaskIdentity, received: Int64, expected: Int64) {
        guard let index = index(identity.itemID), items[index].accepts(identity) else { return }
        let now = Date()
        guard now.timeIntervalSince(lastProgressUpdate[identity] ?? .distantPast) >= 0.25 else { return }
        lastProgressUpdate[identity] = now
        items[index].receivedBytes[identity.part] = max(0, received)
        if expected > 0 { items[index].expectedBytes[identity.part] = expected }
    }

    func receivedFile(_ identity: OfflineTaskIdentity, staging: URL) {
        transfers.removeValue(forKey: identity)
        lastProgressUpdate.removeValue(forKey: identity)
        if let index = index(identity.itemID), restoredUnclaimedItems.contains(identity.itemID),
           items[index].generation == identity.generation, items[index].state == .paused {
            items[index].state = .downloading
            restoredUnclaimedItems.remove(identity.itemID)
        }
        guard let index = index(identity.itemID), items[index].accepts(identity) else {
            try? FileManager.default.removeItem(at: staging)
            return
        }
        do {
            let destination = try PiliOfflineStorage.part(identity.itemID, identity.part)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: staging, to: destination)
            let size = PiliOfflineStorage.size(destination)
            items[index].completedParts.insert(identity.part)
            items[index].receivedBytes[identity.part] = size
            items[index].expectedBytes[identity.part] = size
            try? FileManager.default.removeItem(at: PiliOfflineStorage.resumeFile(identity.itemID, identity.part))
            persist()
            if items[index].isReadyToFinalize { finalize(identity.itemID) }
        } catch { fail(identity.itemID, message: error.localizedDescription) }
    }

    func receivedFailure(_ identity: OfflineTaskIdentity, message: String, resumeData: Data?) {
        transfers.removeValue(forKey: identity)
        guard let index = index(identity.itemID), items[index].generation == identity.generation else { return }
        if let resumeData { saveResumeData(resumeData, identity: identity) }
        guard items[index].state == .downloading else { return }
        fail(identity.itemID, message: message)
    }

    private func restore(_ tasks: [URLSessionTask]) {
        for task in tasks {
            guard let download = task as? URLSessionDownloadTask,
                  let identity = OfflineTaskIdentity(taskDescription: task.taskDescription),
                  let index = index(identity.itemID), items[index].accepts(identity) else {
                task.cancel(); continue
            }
            transfers[identity] = download
            items[index].receivedBytes[identity.part] = max(0, download.countOfBytesReceived)
            if download.countOfBytesExpectedToReceive > 0 {
                items[index].expectedBytes[identity.part] = download.countOfBytesExpectedToReceive
            }
            if download.state == .suspended { download.resume() }
        }
        for index in items.indices {
            if [.downloading, .preparing, .finalizing].contains(items[index].state),
               !transfers.keys.contains(where: { $0.itemID == items[index].id }) {
                items[index].state = items[index].isReadyToFinalize ? .queued : .paused
                if items[index].state == .paused { restoredUnclaimedItems.insert(items[index].id) }
            }
        }
        restoring = false
        persist()
        pump()
    }

    private func pump() {
        guard !restoring, !indexLoadFailed,
              !items.contains(where: { [.preparing, .downloading, .finalizing].contains($0.state) }),
              let next = items.first(where: { $0.state == .queued }) else { return }
        if next.isReadyToFinalize { finalize(next.id); return }
        let client = resolvedAPI()
        guard let index = index(next.id) else { return }
        items[index].state = .preparing
        items[index].generation = UUID()
        let generation = items[index].generation
        persist()
        preparing[next.id] = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.items.first(where: { $0.id == next.id })?.generation == generation { self.preparing[next.id] = nil }
                self.completeBackgroundEventsIfReady()
            }
            do {
                let requestVersion = client.requestSnapshot(purpose: .playback).playbackCredentialVersion
                let data: PlayURLData
                if next.episodeID != nil || next.seasonID != nil {
                    data = try await client.fetchPgcPlayURL(bvid: next.bvid, cid: next.cid, seasonID: next.seasonID,
                                                            epID: next.episodeID, preferredQuality: next.effectiveMediaKind == .audio ? 64 : next.quality)
                } else {
                    data = try await client.fetchPlayURLUncached(bvid: next.bvid, cid: next.cid,
                                                                preferredQuality: next.effectiveMediaKind == .audio ? 64 : next.quality)
                }
                let selection = try PiliOfflineMediaSelection.resolve(item: next, data: data)
                let context = await client.playbackAPIRequestContext()
                guard client.requestSnapshot(purpose: .playback).playbackCredentialVersion == requestVersion else {
                    throw PiliOfflineError.message("取流账号已切换，请重新确认下载")
                }
                guard !Task.isCancelled, let index = self.index(next.id),
                      self.items[index].generation == generation, self.items[index].state == .preparing else { return }
                self.items[index].requiresAudio = selection.urls[.audio] != nil
                self.items[index].codec = selection.codec
                self.items[index].dynamicRange = selection.dynamicRange
                self.items[index].state = .downloading
                self.persist()
                let referer = next.episodeID.map { "https://www.bilibili.com/bangumi/play/ep\($0)" }
                    ?? "https://www.bilibili.com/video/\(next.bvid)"
                let headers = BiliHLSManifestBuilder.httpHeaders(referer: referer, cookieHeader: context.cookieHeader)
                for (part, url) in selection.urls where !self.items[index].completedParts.contains(part) {
                    guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw PiliOfflineError.message("下载地址无效") }
                    let identity = OfflineTaskIdentity(itemID: next.id, generation: generation, part: part)
                    let resumeURL = try PiliOfflineStorage.resumeFile(next.id, part)
                    let task: URLSessionDownloadTask
                    if let resume = try? Data(contentsOf: resumeURL), !resume.isEmpty {
                        task = self.session.downloadTask(withResumeData: resume)
                        try? FileManager.default.removeItem(at: resumeURL)
                    } else {
                        var request = URLRequest(url: url)
                        request.allHTTPHeaderFields = headers
                        request.allowsCellularAccess = UserDefaults.standard.bool(forKey: "piliplus.offline.cellular")
                        task = self.session.downloadTask(with: request)
                    }
                    task.taskDescription = identity.taskDescription
                    self.transfers[identity] = task
                    task.resume()
                }
                self.persist()
                self.cacheDanmaku(next.id)
                if self.items[index].isReadyToFinalize { self.finalize(next.id) }
            } catch {
                guard !Task.isCancelled, self.items.first(where: { $0.id == next.id })?.generation == generation else { return }
                self.fail(next.id, message: error.localizedDescription)
            }
        }
    }

    private func finalize(_ id: UUID) {
        guard let index = index(id), items[index].isReadyToFinalize, finalizing[id] == nil else { return }
        items[index].state = .finalizing
        let item = items[index]
        persist()
        let backgroundToken = UIApplication.shared.beginBackgroundTask(withName: "PiliOfflineMerge") { [weak self] in
            Task { @MainActor in self?.finalizing[id]?.cancel() }
        }
        finalizing[id] = Task { [weak self] in
            guard let self else { return }
            defer {
                if backgroundToken != .invalid { UIApplication.shared.endBackgroundTask(backgroundToken) }
                self.finalizing[id] = nil
                self.pump()
                self.completeBackgroundEventsIfReady()
            }
            do {
                let output = try await PiliOfflineMediaExporter.finalize(item)
                guard !Task.isCancelled, let index = self.index(id), self.items[index].state == .finalizing,
                      self.items[index].generation == item.generation else { return }
                self.items[index].outputFileName = output.lastPathComponent
                self.items[index].fileSize = PiliOfflineStorage.size(output)
                self.items[index].state = .completed
                self.items[index].errorMessage = nil
                if self.persist() {
                    for part in OfflineDownloadPart.allCases {
                        if let file = try? PiliOfflineStorage.part(id, part) { try? FileManager.default.removeItem(at: file) }
                    }
                }
            } catch {
                guard let index = self.index(id), self.items[index].state == .finalizing else { return }
                self.items[index].state = Task.isCancelled ? .paused : .failed
                self.items[index].errorMessage = Task.isCancelled ? "合并暂时中断，点击继续" : error.localizedDescription
                self.persist()
            }
        }
    }

    private func cancelTransfers(for id: UUID, saveResumeData: Bool) {
        let matching = transfers.filter { $0.key.itemID == id }
        for (identity, task) in matching {
            transfers[identity] = nil
            if saveResumeData {
                task.cancel { [weak self] data in
                    guard let data else { return }
                    Task { @MainActor in self?.saveResumeData(data, identity: identity) }
                }
            } else { task.cancel() }
        }
    }

    private func saveResumeData(_ data: Data, identity: OfflineTaskIdentity) {
        guard let index = index(identity.itemID), items[index].generation == identity.generation else { return }
        if let url = try? PiliOfflineStorage.resumeFile(identity.itemID, identity.part) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func fail(_ id: UUID, message: String) {
        guard let index = index(id) else { return }
        items[index].state = .failed
        items[index].errorMessage = message
        cancelTransfers(for: id, saveResumeData: true)
        persist(); pump()
    }
    private func index(_ id: UUID) -> Int? { items.firstIndex { $0.id == id } }
    @discardableResult
    private func persist() -> Bool {
        guard !indexLoadFailed else { return false }
        do { try PiliOfflineStorage.save(items); storageError = nil; return true }
        catch { storageError = "下载记录保存失败：\(error.localizedDescription)"; return false }
    }
    private func resolvedAPI() -> BiliAPIClient {
        if let api { return api }
        let api = BiliAPIClient(sessionStore: SessionStore(), libraryStore: LibraryStore(), homeRecommendDiagnosticsStore: .shared)
        self.api = api
        return api
    }

    func cacheDanmaku(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }),
              ((item.effectiveMediaKind == .video && !item.hasDanmaku) || item.hasSubtitles != true), extras[id] == nil else { return }
        let client = resolvedAPI()
        let token = UUID()
        extraTokens[id] = token
        extras[id] = Task { [weak self] in
            guard let self else { return }
            defer { if self.extraTokens[id] == token { self.extras[id] = nil; self.extraTokens[id] = nil } }
            do {
                if !item.hasDanmaku && item.effectiveMediaKind == .video {
                    let count = max(1, Int(ceil(item.duration / 360)))
                    var records: [PiliOfflineDanmaku] = []
                    var seen = Set<String>()
                    for segment in 1...count {
                        try Task.checkCancellation()
                        let values = try await client.fetchDanmakuSegment(cid: item.cid, segmentIndex: segment)
                        records.append(contentsOf: values.filter { seen.insert($0.id).inserted }.map(PiliOfflineDanmaku.init))
                    }
                    try Task.checkCancellation()
                    guard let index = self.index(id), self.extraTokens[id] == token else { return }
                    let url = try PiliOfflineStorage.directory(id).appendingPathComponent("danmaku.json")
                    try JSONEncoder().encode(records).write(to: url, options: .atomic)
                    self.items[index].hasDanmaku = true
                    self.persist()
                }
                if item.hasSubtitles != true {
                    let tracks = try await client.fetchPiliSubtitleTracks(bvid: item.bvid, cid: item.cid,
                                                                           seasonID: item.seasonID, episodeID: item.episodeID)
                    var subtitles: [PiliCachedSubtitle] = []
                    for track in tracks {
                        try Task.checkCancellation()
                        subtitles.append(PiliCachedSubtitle(track: track, cues: try await client.fetchPiliSubtitles(track)))
                    }
                    try Task.checkCancellation()
                    guard let index = self.index(id), self.extraTokens[id] == token else { return }
                    let url = try PiliOfflineStorage.directory(id).appendingPathComponent("subtitles.json")
                    try JSONEncoder().encode(subtitles).write(to: url, options: .atomic)
                    self.items[index].hasSubtitles = true
                }
                guard let index = self.index(id), self.extraTokens[id] == token else { return }
                self.items[index].extrasError = nil
                self.persist()
            } catch {
                guard !Task.isCancelled, let index = self.index(id), self.extraTokens[id] == token else { return }
                self.items[index].extrasError = "弹幕或字幕尚未完整保存：\(error.localizedDescription)"
                self.persist()
            }
        }
    }
    private var extraTokens: [UUID: UUID] = [:]
}
