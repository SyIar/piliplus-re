import SwiftUI

extension BiliAPIClient {
    func piliLiveFavoriteAreas(identity: PiliAccountIdentity) async throws -> [LiveArea] {
        let data = try await piliAccountAppRequest(path: "/xlive/app-interface/v2/second/get_fav_tag", parameters: [:],
            post: false, identity: identity, base: Self.piliLiveBase)
        guard case .array(let values) = data["tags"] else { throw BiliAPIError.missingPayload }
        var seen = Set<Int>()
        return try values.map { try $0.piliDecode(LiveArea.self) }.filter { $0.id > 0 && seen.insert($0.id).inserted }
    }
    func setPiliLiveFavoriteAreas(_ areas: [LiveArea], identity: PiliAccountIdentity) async throws {
        guard areas.count <= 100, Set(areas.map(\.id)).count == areas.count, areas.allSatisfy({ $0.id > 0 }) else { throw BiliAPIError.missingPayload }
        try await piliAccountAppRequest(path: "/xlive/app-interface/v2/second/set_fav_tag",
            parameters: ["tags": areas.map { String($0.id) }.joined(separator: ",")], post: true, identity: identity, base: Self.piliLiveBase)
    }
}

struct PiliLiveFavoriteAreasView: View {
    let api: BiliAPIClient
    @ObservedObject private var session: SessionStore
    @State private var identity: PiliAccountIdentity?
    @State private var groups: [LiveAreaGroup] = []
    @State private var saved: [LiveArea] = []
    @State private var draft: [LiveArea] = []
    @State private var editing = false
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    init(api: BiliAPIClient) { self.api = api; _session = ObservedObject(wrappedValue: api.sessionStore) }
    var body: some View {
        List {
            Section("我的常用分区") {
                ForEach(draft) { area in
                    if editing { Text(area.name) }
                    else { NavigationLink(area.name) { PiliLiveAreaRoomsView(api: api, title: area.name, parentID: area.parentID, areaID: area.id) } }
                }
                .onDelete { draft.remove(atOffsets: $0) }
                .onMove { draft.move(fromOffsets: $0, toOffset: $1) }
                .deleteDisabled(!editing || busy).moveDisabled(!editing || busy)
                if draft.isEmpty, loaded { Text(editing ? "从下方添加分区" : "尚未添加常用分区") }
            }
            if editing {
                ForEach(groups) { group in
                    Section(group.name) {
                        ForEach(group.children.filter { area in !draft.contains(where: { $0.id == area.id }) }) { area in
                            Button { draft.append(area) } label: { Label(area.name, systemImage: "plus.circle") }
                        }
                    }
                }
            }
            if busy { ProgressView() }
            if let error { Text(error); if !editing { Button("重试") { Task { await load() } } } }
        }
        .environment(\.editMode, .constant(editing ? .active : .inactive))
        .disabled(busy)
        .navigationTitle("常用直播分区").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(editing ? "保存" : "编辑") {
                    if editing { Task { await save() } } else { editing = true }
                }.disabled(busy || !loaded)
            }
            if editing {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { draft = saved; editing = false; error = nil }.disabled(busy) }
            }
        }
        .task(id: session.playbackCredentialVersion) { await load() }
    }
    private func load() async {
        let expected = PiliAccountIdentity(api.requestSnapshot()); identity = expected
        saved = []; draft = []; loaded = false; editing = false; error = nil; busy = true
        defer { if identity == expected { busy = false } }
        do {
            async let areas = api.fetchLiveAreas()
            async let favorites = api.piliLiveFavoriteAreas(identity: expected)
            let values = try await (areas, favorites)
            guard !Task.isCancelled, expected.matches(api.requestSnapshot()) else { return }
            groups = values.0; saved = values.1; draft = values.1; loaded = true
        } catch { if !Task.isCancelled, identity == expected { self.error = error.localizedDescription } }
    }
    private func save() async {
        guard !busy, let expected = identity else { return }; busy = true; error = nil
        let submitted = draft
        defer { if identity == expected { busy = false } }
        do {
            try await api.setPiliLiveFavoriteAreas(submitted, identity: expected)
            guard expected.matches(api.requestSnapshot()) else { return }
            saved = submitted; editing = false
        } catch { if identity == expected { self.error = error.localizedDescription } }
    }
}
