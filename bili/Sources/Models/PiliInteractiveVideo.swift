import Foundation

nonisolated struct PiliInteractiveEdge: Decodable, Sendable {
    struct Edges: Decodable, Sendable { let questions: [Question]? }
    struct Question: Decodable, Sendable { let choices: [Choice]? }
    struct Choice: Codable, Identifiable, Hashable, Sendable {
        let id: Int
        let cid: Int?
        let option: String?
    }
    let edgeID: Int?
    let title: String?
    let edges: Edges?
    var choices: [Choice] { (edges?.questions?.first?.choices ?? []).filter { ($0.cid ?? 0) > 0 } }
    enum CodingKeys: String, CodingKey { case title, edges; case edgeID = "edge_id" }
}

nonisolated struct PiliInteractiveCheckpoint: Codable, Identifiable, Sendable {
    let edgeID: Int?
    let cid: Int
    let title: String
    var id: String { "\(edgeID ?? 0)|\(cid)" }
}
