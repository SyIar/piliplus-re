import Foundation

nonisolated struct MineStatistics: Decodable {
    let following: Int?
    let follower: Int?
    let dynamicCount: Int?
    enum CodingKeys: String, CodingKey {
        case following, follower
        case dynamicCount = "dynamic_count"
    }
}

extension BiliAPIClient {
    func fetchMineStatistics() async throws -> MineStatistics {
        let context = requestSnapshot(purpose: .main)
        let response: BiliResponse<MineStatistics> = try await get(
            base: baseURL, path: "/x/web-interface/nav/stat", query: [:],
            cookieHeader: context.cookieHeader, cachePolicy: .reloadIgnoringLocalCacheData
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let data = response.payload else { throw BiliAPIError.missingPayload }
        return data
    }
}
