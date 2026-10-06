import SwiftUI
import ChunUI

struct PiliMemberExtrasView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    let owner: VideoOwner
    var body: some View {
        PiliList {
            ForEach(PiliMemberSection.allCases) { section in
                NavigationLink(section.title) { PiliMemberSectionView(api: dependencies.api, owner: owner, section: section) }
            }
        }.navigationTitle("更多空间内容")
    }
}

private struct PiliMemberSectionView: View {
    let api: BiliAPIClient
    let owner: VideoOwner
    let section: PiliMemberSection
    @State private var items: [DynamicJSONValue] = []
    @State private var levels: [DynamicJSONValue] = []
    @State private var privilege = -1
    @State private var moreURL: URL?
    @State private var page = 1
    @State private var more = true
    @State private var busy = false
    @State private var error: String?
    @State private var generation = UUID()
    var body: some View {
        PiliList {
            if !levels.isEmpty {
                Picker("充电等级", selection: $privilege) {
                    Text("默认").tag(-1)
                    ForEach(levels, id: \.self) { Text("\($0["name"].piliString) · \($0["member_total"].piliInt) 人").tag($0["privilege_type"].piliInt) }
                }
            }
            ForEach(items, id: \.self) { item in row(item) }
            if let moreURL { AppLinkButton(url: moreURL) { Text("查看店铺更多商品") } }
            if busy { ProgressView() }
            else if let error { Text(error).foregroundStyle(Color.cc.destructive); Button("重试") { Task { await load() } } }
            else if more { Button("加载更多") { Task { await load() } } }
            else if items.isEmpty { PiliUnavailableView("暂无可查看的内容", systemImage: "rectangle.stack", description: Text("该用户可能尚未发布，或未公开此项内容。")) }
        }.navigationTitle(section.title).task { await load(reset: true) }.refreshable { await load(reset: true) }
            .onChange(of: privilege) { Task { await load(reset: true) } }
    }
    @ViewBuilder private func row(_ item: DynamicJSONValue) -> some View {
        if section == .guardList || section == .supporters {
            let mid = section == .guardList ? item["uid"].piliInt : item["mid"].piliInt
            let name = section == .guardList ? item["username"].piliString : item["nickname"].piliString
            let face = section == .guardList ? item["face"].piliString : item["avatar"].piliString
            VideoOwnerRouteLink(owner: .init(mid: mid, name: name, face: face)) {
                HStack { avatar(face); Text(name); Spacer(); Text(section == .guardList ? guardTitle(item["guard_level"].piliInt) : "\(item["day"].piliInt) 天").font(.cc.sm).foregroundStyle(.secondary) }
            }
        } else if section == .favorites, let folder = try? item.piliDecode(FavoriteFolder.self) {
            NavigationLink { PiliPublicFavoriteView(api: api, folder: folder) } label: { card(item) }
        } else if let url = link(item) { AppLinkButton(url: url) { card(item) } }
        else { card(item) }
    }
    private func avatar(_ raw: String) -> some View {
        CachedRemoteImage(url: URL(string: raw.normalizedBiliURL()), targetPixelSize: 120) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.15) }.frame(width: 40, height: 40).clipShape(Circle())
    }
    private func card(_ item: DynamicJSONValue) -> some View {
        HStack(spacing: 12) {
            let raw = section == .shop ? item["cover"]["url"].piliString : item["cover"].piliString
            CachedRemoteImage(url: URL(string: raw.normalizedBiliURL()), targetPixelSize: 240) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.1) }.frame(width: 80, height: 56).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(item["title"].piliString).lineLimit(3)
                if section == .shop {
                    Text("\(item["netPrice"]["pricePrefix"].piliString)\(item["netPrice"]["priceSymbol"].piliString)\(item["netPrice"]["netPrice"].piliString)").font(.cc.sm).foregroundStyle(.secondary)
                    Text(item["itemSourceName"].piliString).font(.cc.sm)
                } else if !item["publish_time_text"].piliString.isEmpty { Text(item["publish_time_text"].piliString).font(.cc.sm).foregroundStyle(.secondary) }
            }
        }
    }
    private func guardTitle(_ value: Int) -> String { switch value { case 1: "总督"; case 2: "提督"; case 3: "舰长"; default: "大航海" } }
    private func link(_ item: DynamicJSONValue) -> URL? {
        switch section {
        case .audio: return URL(string: "https://www.bilibili.com/audio/au\(item["id"].piliInt)")
        case .comic: return URL(string: "https://manga.bilibili.com/detail/mc\(item["param"].piliString)")
        case .courses: return URL(string: "https://www.bilibili.com/cheese/play/ss\(item["season_id"].piliInt)")
        case .shop:
            let raw = item["cardUrl"].piliString
            let nested = URLComponents(string: raw)?.queryItems?.first { $0.name == "url" }?.value
            return URL(string: nested ?? raw)
        default:
            if !item["uri"].piliString.isEmpty { return URL(string: item["uri"].piliString) }
            if item["param"].piliInt > 0 { return URL(string: "https://www.bilibili.com/video/av\(item["param"].piliInt)") }
            return nil
        }
    }
    private func load(reset: Bool = false) async {
        if reset { generation = UUID(); page = 1; items = []; more = true; moreURL = nil }
        else if busy || !more { return }
        let ticket = generation; busy = true; error = nil; defer { if ticket == generation { busy = false } }
        do {
            let result = try await api.piliMemberExtras(section, mid: owner.mid, page: page, privilege: privilege < 0 ? nil : privilege)
            guard generation == ticket, !Task.isCancelled else { return }
            var seen = Set(items); let fresh = result.items.filter { seen.insert($0).inserted }
            items.append(contentsOf: fresh); more = result.more && !fresh.isEmpty; page += 1
            if !result.levels.isEmpty { levels = result.levels }; moreURL = result.moreURL
        } catch { if generation == ticket, !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
