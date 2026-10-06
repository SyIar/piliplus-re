import SwiftUI

struct PiliDynamicAttachments: View {
    let item: DynamicFeedItem
    let api: BiliAPIClient
    @State private var showsVote = false
    private var vote: DynamicJSONValue { item.modules?.moduleDynamic?.additional?.raw["vote"] ?? .null }
    var body: some View {
        let topic = item.modules?.moduleDynamic?.topic ?? .null
        if topic["id"].piliInt > 0 {
            NavigationLink { PiliTopicView(api: api, id: topic["id"].piliInt, name: topic["name"].piliString) }
                label: { Label(topic["name"].piliString, systemImage: "number").font(.subheadline) }
        }
        if vote["vote_id"].piliInt > 0 {
            Button { showsVote = true } label: { Label(vote["desc"].piliString.isEmpty ? "查看投票" : vote["desc"].piliString, systemImage: "chart.bar.xaxis").frame(maxWidth: .infinity, alignment: .leading) }
                .buttonStyle(.bordered)
                .sheet(isPresented: $showsVote) { NavigationStack { PiliVoteView(api: api, id: vote["vote_id"].piliInt, dynamicID: item.idStr) } }
        }
    }
}

struct PiliVoteView: View {
    let api: BiliAPIClient
    let id: Int
    var dynamicID: String?
    @State private var info: DynamicJSONValue = .null
    @State private var selection: Set<Int> = []
    @State private var anonymous = false
    @State private var busy = false
    @State private var error: String?
    @State private var identity: PiliAccountIdentity?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            if let error { Text(error).foregroundStyle(.red) }
            if case .null = info { ProgressView() }
            else {
                Section {
                    Text(info["title"].piliString.isEmpty ? info["desc"].piliString : info["title"].piliString).font(.headline)
                    Text("\(info["join_num"].piliInt) 人参与 · 最多选择 \(max(1, info["choice_cnt"].piliInt)) 项").foregroundStyle(.secondary)
                    if info["end_time"].piliInt > 0 { Text(Date(timeIntervalSince1970: Double(info["end_time"].piliInt)), style: .relative) }
                }
                ForEach(info["options"].piliArray, id: \.self) { option in
                    let key = option["opt_idx"].piliInt
                    Button {
                        if selection.contains(key) { selection.remove(key) }
                        else if selection.count < max(1, info["choice_cnt"].piliInt) { selection.insert(key) }
                    } label: {
                        HStack {
                            if !option["img_url"].piliString.isEmpty {
                                CachedRemoteImage(url: URL(string: option["img_url"].piliString.normalizedBiliURL()), targetPixelSize: 220) { $0.resizable().scaledToFit() } placeholder: { Color.clear }.frame(width: 70, height: 70)
                            }
                            Text(option["opt_desc"].piliString); Spacer()
                            if !info["my_votes"].piliArray.isEmpty || ended { Text("\(option["cnt"].piliInt) 票").foregroundStyle(.secondary) }
                            Image(systemName: selection.contains(key) ? "checkmark.circle.fill" : "circle")
                        }
                    }.disabled(ended || busy)
                }
                Toggle("匿名投票", isOn: $anonymous)
                Button("提交投票") { Task { await vote() } }.disabled(selection.isEmpty || ended || busy || identity == nil)
                if ended { Text("投票已结束").foregroundStyle(.secondary) }
            }
        }.navigationTitle("投票").toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .task { identity = .init(api.requestSnapshot(purpose: .main)); await load() }
    }
    private var ended: Bool { info["end_time"].piliInt > 0 && Double(info["end_time"].piliInt) <= Date().timeIntervalSince1970 }
    private func load() async {
        do { info = try await api.piliVote(id: id); selection = Set(info["my_votes"].piliArray.map(\.piliInt)); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func vote() async {
        guard let identity, !busy else { return }; busy = true; defer { busy = false }
        do { info = try await api.piliCastVote(id: id, options: selection, anonymous: anonymous, dynamicID: dynamicID, identity: identity); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct PiliTopicView: View {
    let api: BiliAPIClient
    let id: Int
    var name = "话题"
    @State private var info: DynamicJSONValue = .null
    @State private var items: [DynamicFeedItem] = []
    @State private var sorts: [DynamicJSONValue] = []
    @State private var sort = 0
    @State private var offset = ""
    @State private var hasMore = false
    @State private var folded = false
    @State private var loading = false
    @State private var mutating = false
    @State private var composer = false
    @State private var error: String?
    @State private var identity: PiliAccountIdentity?
    @State private var generation = UUID()
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text(info["name"].piliString.isEmpty ? name : info["name"].piliString).font(.title2.bold())
                if !info["description"].piliString.isEmpty { Text(info["description"].piliString) }
                HStack {
                    Button(info["is_fav"].piliInt == 1 ? "取消收藏" : "收藏话题") { action(favorite: info["is_fav"].piliInt != 1) }
                    Button(info["is_like"].piliInt == 1 ? "取消点赞" : "点赞") { action(like: info["is_like"].piliInt != 1) }
                    Button("参与讨论") { composer = true }
                }.buttonStyle(.bordered).disabled(mutating)
                if !sorts.isEmpty {
                    Picker("排序", selection: $sort) { ForEach(sorts, id: \.self) { Text($0["sort_name"].piliString).tag($0["sort_by"].piliInt) } }.pickerStyle(.segmented)
                }
                if let error { Text(error).foregroundStyle(.red); Button("重试") { Task { await load(reset: items.isEmpty) } } }
                ForEach(items) { DynamicFeedCard(item: $0, api: api) }
                if loading { ProgressView() }
                else if hasMore { Button("加载更多") { Task { await load(reset: false) } } }
                if folded { Button("查看折叠动态") { Task { await load(reset: false, fold: true) } }.disabled(loading) }
            }.padding()
        }.navigationTitle("话题").navigationBarTitleDisplayMode(.inline)
            .task {
                identity = .init(api.requestSnapshot(purpose: .main))
                do { info = try await api.piliContentRead("/x/topic/web/details/top", query: ["topic_id": String(id), "source": "Web"])["top_details"]["topic_item"] }
                catch { self.error = error.localizedDescription }
                await load(reset: true)
            }
            .onChange(of: sort) { _, _ in Task { await load(reset: true) } }
            .sheet(isPresented: $composer) {
                let draft = { var d = PiliDynamicDraft(); d.topicID = id; d.topicName = info["name"].piliString.isEmpty ? name : info["name"].piliString; return d }()
                PiliDynamicComposer(api: api, initial: draft) { Task { await load(reset: true) } }
            }
    }
    private func load(reset: Bool, fold: Bool = false) async {
        if reset { generation = UUID(); offset = ""; items = []; folded = false }
        else if loading { return }
        let token = generation; loading = true; error = nil
        defer { if token == generation { loading = false } }
        do {
            let page = try await api.piliTopic(id: id, offset: offset, sort: sort, folded: fold)
            guard token == generation, !Task.isCancelled else { return }
            var seen = Set(items.map(\.id))
            for card in page["items"].piliArray {
                if let item = try? card["dynamic_card_item"].piliDecode(DynamicFeedItem.self), seen.insert(item.id).inserted { items.append(item) }
                if card["fold_card_item"]["fold_count"].piliInt > 0 { folded = true }
            }
            if fold { folded = false }
            else {
                let next = page["offset"].piliString
                hasMore = page["has_more"].piliInt == 1 && !next.isEmpty && next != offset; offset = next
                sorts = page["topic_sort_by_conf"]["all_sort_by"].piliArray
            }
        } catch { if token == generation { self.error = error.localizedDescription } }
    }
    private func action(favorite: Bool? = nil, like: Bool? = nil) {
        guard let identity, !mutating else { return }; mutating = true
        Task {
            defer { mutating = false }
            do {
                try await api.piliTopicAction(id: id, favorite: favorite, like: like, identity: identity)
                var value = info.piliObject
                if let favorite { value["is_fav"] = .bool(favorite) }
                if let like { value["is_like"] = .bool(like) }
                info = .object(value)
            } catch { self.error = error.localizedDescription }
        }
    }
}
