import SwiftUI
import ChunUI

struct PiliDynamicReservationView: View {
    let api: BiliAPIClient
    let dynamicID: String
    @State private var value: DynamicJSONValue
    @State private var identity: PiliAccountIdentity?
    @State private var busy = false
    @State private var error: String?
    @Environment(\.openURL) private var openURL
    init(api: BiliAPIClient, dynamicID: String, value: DynamicJSONValue) {
        self.api = api; self.dynamicID = dynamicID; _value = State(initialValue: value)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PiliLabel(value["title"].piliString, systemImage: "calendar.badge.clock").piliFont(.baseBold)
            Text(value["desc1"]["text"].piliString + " · " + value["desc2"]["text"].piliString)
                .piliFont(.sm).foregroundStyle(.secondary)
            let button = value["button"]
            let checked = button["status"].piliInt == button["type"].piliInt
            Button {
                let jump = button["jump_url"].piliString.normalizedBiliURL()
                if !jump.isEmpty, let url = URL(string: jump) { openURL(url) }
                else { Task { await toggle() } }
            } label: {
                let text = button["jump_text"].piliString.isEmpty
                    ? button[checked ? "check_text" : "uncheck_text"].piliString : button["jump_text"].piliString
                PiliLabel(text.isEmpty ? (checked ? "取消预约" : "预约") : text, systemImage: checked ? "checkmark.circle" : "bell.badge")
            }.buttonStyle(.glass).disabled(busy || button["disable"].piliInt == 1)
            if let error { Text(error).piliFont(.sm).foregroundStyle(.secondary) }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .piliGlassCard(radius: 14)
            .onAppear { if identity == nil { identity = .init(api.requestSnapshot()) } }
    }
    private func toggle() async {
        guard !busy, let identity else { return }; busy = true; error = nil; defer { busy = false }
        do {
            let result = try await api.piliToggleDynamicReservation(id: value["rid"].piliInt, dynamicID: dynamicID,
                status: value["button"]["status"].piliInt, total: value["reserve_total"].piliInt, identity: identity)
            var updated = value.piliObject, button = value["button"].piliObject, desc = value["desc2"].piliObject
            if result.piliObject["final_btn_status"] != nil { button["status"] = result["final_btn_status"] }
            if result.piliObject["desc_update"] != nil { desc["text"] = result["desc_update"] }
            if result.piliObject["reserve_update"] != nil { updated["reserve_total"] = result["reserve_update"] }
            updated["button"] = .object(button); updated["desc2"] = .object(desc); value = .object(updated)
        } catch { self.error = error.localizedDescription }
    }
}

extension BiliAPIClient {
    func piliToggleDynamicReservation(id: Int, dynamicID: String, status: Int, total: Int, identity: PiliAccountIdentity) async throws -> DynamicJSONValue {
        guard id > 0, Int64(dynamicID) ?? 0 > 0 else { throw BiliAPIError.missingPayload }
        return try await piliContentWrite("/x/dynamic/feed/reserve/click", body: .object([
            "reserve_id": .int(id), "dynamic_id_str": .string(dynamicID), "cur_btn_status": .int(status),
            "reserve_total": .int(total)]), identity: identity)
    }
}
