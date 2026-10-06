import Foundation

nonisolated struct PiliOfflineDanmaku: Codable, Sendable {
    let id: String
    let time: Double
    let mode: Int
    let fontSize: Double
    let color: UInt32
    let text: String
    let senderHash: String?
    let vipColor: Bool?
    init(_ item: DanmakuItem) {
        id = item.id; time = item.time; mode = item.mode; fontSize = item.fontSize; color = item.color; text = item.text; senderHash = item.senderHash; vipColor = item.isVIPColor
    }
    var item: DanmakuItem { DanmakuItem(id: id, time: time, mode: mode, fontSize: fontSize, color: color, text: text, isVIPColor: vipColor ?? false, senderHash: senderHash) }
    static func load(_ id: UUID) -> [DanmakuItem] {
        guard let root = try? PiliOfflineStorage.directory(id),
              let data = try? Data(contentsOf: root.appendingPathComponent("danmaku.json")),
              let values = try? JSONDecoder().decode([Self].self, from: data) else { return [] }
        return values.map(\.item).sorted { $0.time < $1.time }
    }
}
