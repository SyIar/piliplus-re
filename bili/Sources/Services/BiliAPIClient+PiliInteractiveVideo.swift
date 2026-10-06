import Foundation
import PiliPlaybackCore

extension BiliAPIClient {
    func fetchPiliInteractiveEdge(bvid: String, graphVersion: Int, edgeID: Int?) async throws -> PiliInteractiveEdge {
        let context = await playbackAPIRequestContext()
        var query = ["bvid": bvid, "graph_version": String(graphVersion)]
        if let edgeID { query["edge_id"] = String(edgeID) }
        let response: BiliResponse<PiliInteractiveEdge> = try await get(
            base: baseURL, path: "/x/stein/edgeinfo_v2", query: query, cookieHeader: context.cookieHeader
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let edge = response.payload else { throw BiliAPIError.missingPayload }
        return edge
    }
}
