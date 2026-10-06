import Combine
import Foundation

@MainActor
final class PiliSuperChatStore: ObservableObject {
    @Published private(set) var items: [PiliSuperChat] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published var mode = UserDefaults.standard.object(forKey: "piliplus.live.superChat") as? Int ?? 1 {
        didSet { UserDefaults.standard.set(mode, forKey: "piliplus.live.superChat") }
    }
    private var loadedRoom: Int?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    deinit { task?.cancel() }

    func ingest(_ values: [PiliSuperChat]) {
        guard mode != 0, !values.isEmpty else { return }
        var byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for value in values { byID[value.id] = value }
        let next = Array(byID.values.sorted { $0.start == $1.start ? $0.id > $1.id : $0.start > $1.start }.prefix(200))
        if next != items { items = next }
    }
    func visible(at date: Date) -> [PiliSuperChat] {
        switch mode { case 0: []; case 1: items.filter { $0.end > date }; default: items }
    }
    func load(roomID: Int, api: BiliAPIClient, force: Bool = false) {
        guard mode != 0, task == nil, force || loadedRoom != roomID else { return }
        loading = true; error = nil
        let revision = UUID(); generation = revision
        task = Task { [weak self] in
            defer { if let self, self.generation == revision { self.task = nil; self.loading = false } }
            do {
                let values = try await api.piliSuperChats(roomID: roomID)
                guard !Task.isCancelled, let self, self.generation == revision else { return }
                self.ingest(values); self.loadedRoom = roomID
            } catch { if !Task.isCancelled, let self, self.generation == revision { self.error = error.localizedDescription } }
        }
    }
    func stop(clear: Bool) {
        generation = UUID(); task?.cancel(); task = nil; loading = false
        if clear { items = []; loadedRoom = nil; error = nil }
    }
}
