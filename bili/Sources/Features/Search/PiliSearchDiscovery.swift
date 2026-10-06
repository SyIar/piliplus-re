import Foundation

enum PiliSearchDuration: Int, CaseIterable, Identifiable {
    case any = 0, short, medium, long, extraLong
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .any: "全部时长"
        case .short: "10分钟内"
        case .medium: "10–30分钟"
        case .long: "30–60分钟"
        case .extraLong: "60分钟以上"
        }
    }
}

nonisolated struct PiliDefaultSearch: Equatable, Sendable {
    let keyword: String
    let display: String
}

/// Only explicit submitted searches are saved. Typing suggestions never writes history.
@MainActor
final class PiliSearchHistory {
    private let defaults: UserDefaults
    private let key = "piliplus.search.history"
    var values: [String] { Array((defaults.stringArray(forKey: key) ?? []).prefix(30)) }
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func record(_ term: String, enabled: Bool) {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, !term.isEmpty, term.utf8.count <= 1_024 else { return }
        var next = values.filter { $0 != term }; next.insert(term, at: 0)
        let bounded = Array(next.prefix(30))
        if bounded != values { defaults.set(bounded, forKey: key) }
    }
    func remove(_ term: String) { defaults.set(values.filter { $0 != term }, forKey: key) }
    func clear() { defaults.removeObject(forKey: key) }
}
