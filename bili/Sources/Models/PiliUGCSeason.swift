import Foundation

nonisolated struct PiliUGCSeason: Decodable, Hashable, Sendable {
    let id: Int?
    let title: String?
    let cover: String?
    let mid: Int?
    let sections: [Section]?

    struct Section: Decodable, Hashable, Sendable, Identifiable {
        let id: Int?
        let title: String?
        let episodes: [Episode]?
    }
    struct Episode: Decodable, Hashable, Sendable {
        let aid: Int?
        let cid: Int?
        let bvid: String?
        let title: String?
        let arc: Arc?
        let page: VideoPage?
        let pages: [VideoPage]?
    }
    struct Arc: Decodable, Hashable, Sendable {
        let title: String?
        let pic: String?
        let duration: Int?
        let author: VideoOwner?
    }
    func videos(defaultOwner: VideoOwner?) -> [VideoItem] {
        var seen = Set<String>()
        return (sections ?? []).flatMap { $0.episodes ?? [] }.compactMap { item in
            guard let bvid = item.bvid, !bvid.isEmpty, seen.insert(bvid).inserted else { return nil }
            return VideoItem(bvid: bvid, aid: item.aid, title: item.title ?? item.arc?.title ?? bvid,
                             pic: item.arc?.pic ?? cover, desc: nil, duration: item.arc?.duration,
                             pubdate: nil, owner: item.arc?.author ?? defaultOwner, stat: nil,
                             cid: item.cid ?? item.page?.cid, pages: item.pages ?? item.page.map { [$0] }, dimension: nil)
        }
    }
}
