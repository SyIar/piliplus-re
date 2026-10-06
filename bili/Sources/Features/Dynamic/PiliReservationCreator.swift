import SwiftUI
import ChunUI

nonisolated struct PiliReservationDraft: Codable, Equatable, Sendable {
    var id: Int
    var title: String
    var date: Date
    var subtype: Int
}

struct PiliReservationCreator: View {
    let api: BiliAPIClient
    let identity: PiliAccountIdentity
    let initial: PiliReservationDraft?
    let onSave: (PiliReservationDraft) -> Void
    @PiliDismiss private var dismiss
    @State private var title = ""
    @State private var date = Date().addingTimeInterval(86400)
    @State private var subtype = 0
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            PiliForm {
                TextField("直播标题", text: $title)
                Picker("类型", selection: $subtype) { Text("公开直播").tag(0); Text("大航海直播").tag(1) }
                DatePicker("开播时间", selection: $date, in: Date()...Date().addingTimeInterval(90 * 86400))
                Text("至少选择 5 分钟之后；预约发布后可从动态查看。").font(.cc.sm).foregroundStyle(.secondary)
                if let message { Text(message).foregroundStyle(Color.cc.destructive) }
                if busy { ProgressView() }
            }.disabled(busy).navigationTitle("直播预约")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(busy) }
                }.piliInteractiveDismissDisabled(busy)
                .task { if let initial { title = initial.title; date = initial.date; subtype = initial.subtype } }
        }
    }
    private func save() async {
        guard !busy else { return }; busy = true; message = nil; defer { busy = false }
        do {
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 60,
                  date.timeIntervalSinceNow >= 300, date.timeIntervalSinceNow <= 90 * 86400 else { throw PiliOfflineError.message("请输入最多 60 字的标题，时间需在 5 分钟到 90 天内") }
            var fields = ["type": "2", "sub_type": String(subtype), "from": "1", "title": title, "live_plan_start_time": String(Int(date.timeIntervalSince1970))]
            if let initial { fields["id"] = String(initial.id) }
            let value = try await api.piliContentWrite(initial == nil ? "/x/new-reserve/up/reserve/create" : "/x/new-reserve/up/reserve/update", fields: fields, identity: identity)
            let id = value["sid"].piliInt > 0 ? value["sid"].piliInt : initial?.id ?? 0
            guard id > 0 else { throw BiliAPIError.missingPayload }
            onSave(.init(id: id, title: title, date: date, subtype: subtype)); dismiss()
        } catch { message = error.localizedDescription }
    }
}
