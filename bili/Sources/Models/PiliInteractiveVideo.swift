import Foundation
import PiliPlaybackCore

typealias PiliInteractiveEdge = InteractiveNode

nonisolated struct PiliInteractiveCheckpoint: Codable, Identifiable, Sendable {
    let visitID: UUID
    let edgeID: Int?
    let cid: Int
    let title: String
    let session: InteractiveSession?
    let noBacktracking: Bool
    let noTutorial: Bool
    var id: String { visitID.uuidString }
    init(visitID: UUID = UUID(), edgeID: Int?, cid: Int, title: String,
         session: InteractiveSession? = nil, noBacktracking: Bool = false, noTutorial: Bool = false) {
        self.visitID = visitID; self.edgeID = edgeID; self.cid = cid; self.title = title
        self.session = session; self.noBacktracking = noBacktracking; self.noTutorial = noTutorial
    }
    enum CodingKeys: String, CodingKey { case visitID, edgeID, cid, title, session, noBacktracking, noTutorial }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        visitID = try c.decodeIfPresent(UUID.self, forKey: .visitID) ?? UUID()
        edgeID = try c.decodeIfPresent(Int.self, forKey: .edgeID)
        cid = try c.decode(Int.self, forKey: .cid)
        title = try c.decode(String.self, forKey: .title)
        session = try c.decodeIfPresent(InteractiveSession.self, forKey: .session)
        noBacktracking = try c.decodeIfPresent(Bool.self, forKey: .noBacktracking) ?? false
        noTutorial = try c.decodeIfPresent(Bool.self, forKey: .noTutorial) ?? false
    }
}
