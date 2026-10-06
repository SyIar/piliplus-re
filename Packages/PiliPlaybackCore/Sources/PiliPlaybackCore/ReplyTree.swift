import Foundation

/// A bounded-layout, iterative forest. Missing parents stay visible until a later
/// page supplies them; malformed cycles never hide replies or recurse forever.
public struct ReplyTree: Sendable {
    public struct Entry: Sendable {
        public let id: Int
        public let parentID: Int?
        public init(id: Int, parentID: Int?) { self.id = id; self.parentID = parentID }
    }
    public struct Row: Identifiable, Equatable, Sendable {
        public let id: Int
        public let depth: Int
        public let isMissing: Bool
        public let descendantCount: Int
    }
    public let rows: [Row]
    private let parents: [Int: Int]
    private let rootID: Int

    public init(rootID: Int, entries: [Entry]) {
        self.rootID = rootID
        var order: [Int] = [], known = Set<Int>(), parents: [Int: Int] = [:]
        for entry in entries where entry.id > 0 && entry.id != rootID {
            guard known.insert(entry.id).inserted else { continue }
            order.append(entry.id)
            let parent = entry.parentID ?? rootID
            parents[entry.id] = parent > 0 && parent != entry.id ? parent : rootID
        }
        let actual = known
        for id in order {
            if let parent = parents[id], parent != rootID, known.insert(parent).inserted {
                parents[parent] = rootID
            }
        }
        order.append(contentsOf: known.subtracting(actual).sorted())
        var finished = Set<Int>()
        for id in order where !finished.contains(id) {
            var path: [Int] = [], visiting = Set<Int>(), cursor = id
            while cursor != rootID && !finished.contains(cursor) {
                if !visiting.insert(cursor).inserted { parents[cursor] = rootID; break }
                path.append(cursor)
                cursor = parents[cursor] ?? rootID
            }
            finished.formUnion(path)
        }
        var children: [Int: [Int]] = [:]
        for id in order { children[parents[id] ?? rootID, default: []].append(id) }
        var stack = (children[rootID] ?? []).reversed().map { ($0, 0) }
        var traversal: [(Int, Int)] = []
        while let (id, depth) = stack.popLast() {
            traversal.append((id, depth))
            for child in (children[id] ?? []).reversed() { stack.append((child, depth + 1)) }
        }
        var counts: [Int: Int] = [:]
        for (id, _) in traversal.reversed() {
            counts[parents[id] ?? rootID, default: 0] += counts[id, default: 0] + (actual.contains(id) ? 1 : 0)
        }
        rows = traversal.map { Row(id: $0.0, depth: $0.1, isMissing: !actual.contains($0.0), descendantCount: counts[$0.0, default: 0]) }
        self.parents = parents
    }

    public func visibleRows(collapsed: Set<Int>) -> [Row] {
        var result: [Row] = [], hiddenBelow: Int?
        for row in rows {
            if let depth = hiddenBelow, row.depth > depth { continue }
            hiddenBelow = collapsed.contains(row.id) ? row.depth : nil
            result.append(row)
        }
        return result
    }

    public func ancestors(of id: Int) -> Set<Int> {
        var result = Set<Int>(), cursor = parents[id]
        while let parent = cursor, parent != rootID, result.insert(parent).inserted { cursor = parents[parent] }
        return result
    }
}
