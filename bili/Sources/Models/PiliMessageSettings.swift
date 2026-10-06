import Foundation
import PiliPlaybackCore

nonisolated struct PiliIMSetting: Identifiable, Equatable, Sendable {
    let id: Int
    var raw: PiliProtoMessage
    var kind: Int { (1...4).first { raw.has($0) } ?? 0 }
    var content: PiliProtoMessage { (try? raw.message(kind)) ?? .init() }
    var title: String {
        switch kind { case 1: content.string(2); case 3: content.string(3); case 4: content.string(1); default: "" }
    }
    var subtitle: String { kind == 1 ? content.string(3) : content.string(4) }
    var isOn: Bool { content.integer(1) == 1 }
    var parentType: Int { ((try? content.message(1)) ?? .init()).integer(4) }
    var isPage: Bool { kind == 3 && content.has(1) }
    var choices: [PiliProtoMessage] {
        if kind == 2 { return (try? content.messages(1)) ?? [] }
        if kind == 3 { return (try? content.message(7).messages(2)) ?? [] }
        return []
    }
    var url: URL? {
        let other = (try? content.message(2)) ?? .init()
        let popup = (try? content.message(6)) ?? .init()
        return URL(string: other.string(1).isEmpty ? popup.string(3) : other.string(1))
    }
    func toggled(_ enabled: Bool) -> Self {
        var value = self, toggle = content
        toggle.set(1, integer: enabled ? 1 : 0); value.raw.set(1, message: toggle); return value
    }
    func selecting(_ index: Int) -> Self {
        guard choices.indices.contains(index) else { return self }
        var value = self, items = choices, container = content
        for i in items.indices { items[i].set(3, integer: i == index ? 1 : 0) }
        if kind == 2 { container.set(1, messages: items); value.raw.set(2, message: container) }
        else {
            var window = (try? container.message(7)) ?? .init(); window.set(2, messages: items)
            container.set(7, message: window); container.set(5, string: items[index].string(2)); value.raw.set(3, message: container)
        }
        return value
    }
    static func decode(_ reply: PiliProtoMessage) throws -> [Self] {
        try reply.messages(2).map { entry in Self(id: entry.integer(1), raw: try entry.message(2)) }.sorted { $0.id < $1.id }
    }
    var updateRequest: PiliProtoMessage {
        var entry = PiliProtoMessage(); entry.set(1, integer: id); entry.set(2, message: raw)
        var request = PiliProtoMessage(); request.set(1, messages: [entry]); return request
    }
}
