import SwiftUI
import ChunUI
import Charts

struct PiliSupplementView: View {
    let api: BiliAPIClient
    let route: PiliSupplementRoute
    var body: some View {
        switch route {
        case .audio(let id): PiliAudioView(api: api, id: id)
        case .music(let id): PiliMusicView(api: api, id: id)
        case .bubble(let id): PiliBubbleView(api: api, id: id)
        case .match(let id): PiliMatchView(api: api, id: id)
        }
    }
}

struct PiliMusicView: View {
    let api: BiliAPIClient
    let id: String
    @State private var detail: DynamicJSONValue = .null
    @State private var recommendations: [DynamicJSONValue] = []
    @State private var identity: PiliAccountIdentity?
    @State private var wished = false
    @State private var busy = false
    @State private var error: String?
    @State private var comments: DynamicFeedItem?
    var body: some View {
        PiliList {
            if !detail.piliObject.isEmpty {
                Section {
                    Text(detail["music_title"].piliString).font(.cc.lgBold.bold())
                    Text(detail["origin_artist"].piliString).foregroundStyle(.secondary)
                    ForEach(["album", "music_publish", "music_source"], id: \.self) { key in
                        if !detail[key].piliString.isEmpty { Text(detail[key].piliString).font(.cc.base) }
                    }
                    ForEach(detail["artists_list"].piliArray, id: \.self) { artist in
                        if let owner = try? artist.piliDecode(VideoOwner.self), owner.mid > 0 {
                            VideoOwnerRouteLink(owner: owner) { Text("\(owner.name) · \(artist["identity"].piliString)") }
                        }
                    }
                    if !detail["mv_bvid"].piliString.isEmpty, let url = URL(string: "https://www.bilibili.com/video/\(detail["mv_bvid"].piliString)") {
                        AppLinkButton(url: url) { PiliLabel("播放 MV", systemImage: "play.circle.fill") }
                    }
                    PiliIconButton(wished ? "已想听" : "想听", systemImage: wished ? "heart.fill" : "heart") { wish() }.disabled(busy)
                    let target = detail["music_comment"]
                    if target["oid"].piliInt > 0 {
                        PiliIconButton("音乐评论", systemImage: "bubble") { comments = try? piliCommentTarget(oid: target["oid"].piliString, type: target["page_type"].piliInt > 0 ? target["page_type"].piliInt : 47) }
                    }
                    ShareLink(item: URL(string: "https://music.bilibili.com/h5/music-detail?music_id=\(id)")!)
                }
                if !detail["achievement"].piliArray.isEmpty {
                    Section("成就") { ForEach(detail["achievement"].piliArray, id: \.self) { Text($0.piliString) } }
                }
                let heat = Array(detail["hot_song_heat"]["song_heat"].piliArray.prefix(366))
                if !heat.isEmpty {
                    Section("热度趋势") {
                        Chart(heat, id: \.self) { point in
                            LineMark(x: .value("日期", Date(timeIntervalSince1970: Double(point["date"].piliInt))), y: .value("热度", point["heat"].piliInt))
                        }.frame(height: 160)
                    }
                }
                Section("使用这首音乐的视频") {
                    ForEach(recommendations, id: \.self) { item in
                        if let url = URL(string: "https://www.bilibili.com/video/\(item["bvid"].piliString)"), !item["bvid"].piliString.isEmpty {
                            AppLinkButton(url: url) { VStack(alignment: .leading) { Text(item["title"].piliString); Text(item["up_nick_name"].piliString).font(.cc.sm).foregroundStyle(.secondary) } }
                        }
                    }
                }
            }
            if busy { ProgressView() }
            if let error { Text(error).foregroundStyle(Color.cc.destructive); Button("重试") { Task { await load() } } }
        }.navigationTitle("音乐详情").task { await load() }.refreshable { await load() }
            .piliSheet(item: $comments) { DynamicCommentsSheet(item: $0, api: api) }
    }
    private func load() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            identity = PiliAccountIdentity(api.requestSnapshot())
            async let info = api.piliMusic(id)
            async let related = api.piliMusicRecommendations(id)
            detail = try await info; wished = detail["wish_listen"].piliInt != 0
            recommendations = try await related; error = nil
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func wish() {
        guard !busy, let identity else { return }; busy = true
        Task {
            defer { busy = false }
            do { try await api.piliMusicWish(id, selected: wished, identity: identity); wished.toggle(); error = nil }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct PiliBubbleView: View {
    let api: BiliAPIClient
    let id: String
    @State private var title = "小站"
    @State private var categories: [DynamicJSONValue] = []
    @State private var sorts: [DynamicJSONValue] = []
    @State private var category = ""
    @State private var sort = -1
    @State private var items: [DynamicJSONValue] = []
    @State private var page = 1
    @State private var more = true
    @State private var busy = false
    @State private var error: String?
    @State private var generation = UUID()
    var body: some View {
        PiliList {
            if !categories.isEmpty {
                Picker("分类", selection: $category) {
                    Text("全部").tag("")
                    ForEach(categories, id: \.self) { item in if !item["id"].piliString.isEmpty { Text(item["name"].piliString).tag(item["id"].piliString) } }
                }
            }
            if !sorts.isEmpty { Picker("排序", selection: $sort) { Text("默认").tag(-1); ForEach(sorts, id: \.self) { Text($0["text"].piliString).tag($0["sort_type"].piliInt) } } }
            ForEach(items, id: \.self) { item in
                if let url = URL(string: "https://t.bilibili.com/\(item["dyn_id"].piliString)") {
                    AppLinkButton(url: url) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item["title"].piliString)
                            Text("\(item["meta"]["author"].piliString) · \(item["meta"]["time_text"].piliString)").font(.cc.sm).foregroundStyle(.secondary)
                            Text("\(item["meta"]["view_stat"].piliString) · \(item["meta"]["reply_count"].piliString) 评论").font(.cc.sm).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if busy { ProgressView() }
            else if let error { Text(error).foregroundStyle(Color.cc.destructive); Button("重试") { Task { await load() } } }
            else if more { Button("加载更多") { Task { await load() } } }
            else if items.isEmpty { Text("暂无内容") }
        }.navigationTitle(title).task { await load(reset: true) }.refreshable { await load(reset: true) }
            .onChange(of: category) { Task { await load(reset: true) } }.onChange(of: sort) { Task { await load(reset: true) } }
    }
    private func load(reset: Bool = false) async {
        if reset { generation = UUID(); page = 1; items = []; more = true }
        else if busy || !more { return }
        let ticket = generation; busy = true; error = nil; defer { if generation == ticket { busy = false } }
        do {
            let data = try await api.piliBubble(id: id, category: category, sort: sort < 0 ? nil : sort, page: page)
            guard generation == ticket, !Task.isCancelled else { return }
            if !data["base_info"]["tribe_info"]["title"].piliString.isEmpty { title = data["base_info"]["tribe_info"]["title"].piliString + "小站" }
            if !data["category"]["category_list"].piliArray.isEmpty { categories = data["category"]["category_list"].piliArray }
            sorts = data["sort_info"]["sort_items"].piliArray
            let list = data["content"]["dyn_list"].piliArray
            var seen = Set(items.map { $0["dyn_id"].piliString }); let fresh = list.filter { !$0["dyn_id"].piliString.isEmpty && seen.insert($0["dyn_id"].piliString).inserted }
            items.append(contentsOf: fresh); more = list.count >= 20 && !fresh.isEmpty; page += 1
        } catch { if generation == ticket, !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct PiliMatchView: View {
    let api: BiliAPIClient
    let id: Int
    @State private var contest: DynamicJSONValue = .null
    @State private var comments: DynamicFeedItem?
    @State private var error: String?
    var body: some View {
        PiliList {
            if !contest.piliObject.isEmpty {
                Text(contest["season"]["title"].piliString).font(.cc.baseBold)
                Text(contest["game_stage"].piliString).foregroundStyle(.secondary)
                HStack(alignment: .top) {
                    team(contest["home_team"])
                    Spacer()
                    Text(contest["contest_status"].piliInt == 1 ? "VS" : "\(contest["home_score"].piliInt) : \(contest["away_score"].piliInt)").font(.cc.lgBold.bold())
                    Spacer(); team(contest["away_team"])
                }
                Text(Date(timeIntervalSince1970: Double(contest["stime"].piliInt)), format: .dateTime.year().month().day().hour().minute())
                if contest["contest_status"].piliInt == 2, contest["live_room"].piliInt > 0,
                   let url = URL(string: "https://live.bilibili.com/\(contest["live_room"].piliInt)") {
                    AppLinkButton(url: url) { PiliLabel("观看直播", systemImage: "play.circle") }
                }
                if contest["contest_status"].piliInt == 3 { Text("比赛已结束").foregroundStyle(.secondary) }
                PiliIconButton("比赛讨论", systemImage: "bubble") { comments = try? piliCommentTarget(oid: String(id), type: 27) }
            } else if error == nil { ProgressView() }
            if let error { Text(error).foregroundStyle(Color.cc.destructive); Button("重试") { Task { await load() } } }
        }.navigationTitle("比赛详情").task { await load() }.refreshable { await load() }
            .piliSheet(item: $comments) { DynamicCommentsSheet(item: $0, api: api) }
    }
    private func team(_ value: DynamicJSONValue) -> some View {
        VStack {
            let logo = value["logo"].piliString
            CachedRemoteImage(url: URL(string: logo.hasPrefix("/") ? "https://i1.hdslb.com" + logo : logo), targetPixelSize: 150) { $0.resizable().scaledToFit() } placeholder: { Color.clear }.frame(width: 50, height: 50)
            Text(value["title"].piliString).font(.cc.base)
        }.frame(maxWidth: .infinity)
    }
    private func load() async {
        do { contest = try await api.piliMatch(id); error = contest.piliObject.isEmpty ? "比赛暂不可查看" : nil }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
