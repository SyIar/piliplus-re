import Foundation

nonisolated struct PiliNoteRecord: Identifiable, Sendable {
    let noteID: String?
    let articleID: String?
    let aid: Int?
    let title: String
    let summary: String
    let author: String?
    var id: String { noteID ?? articleID ?? "\(aid ?? 0)" }
    init?(_ value: DynamicJSONValue) {
        guard case let .object(object) = value else { return nil }
        noteID = object["note_id"]?.textValue
        articleID = object["cvid"]?.textValue
        guard noteID != nil || articleID != nil else { return nil }
        let arc = object["arc"]?.objectValueForDynamicParsing ?? [:]
        aid = arc["oid"]?.intValueForDynamicParsing ?? object["oid"]?.intValueForDynamicParsing
        title = object["title"]?.textValue ?? arc["title"]?.textValue ?? "视频笔记"
        summary = object["summary"]?.textValue ?? ""
        author = object["author"]?.objectValueForDynamicParsing?["name"]?.textValue
    }
}

nonisolated struct PiliNoteDetail: Sendable {
    let title: String
    let content: String
    let aid: Int?
    let forbidsEditing: Bool
    init(_ object: [String: DynamicJSONValue]) {
        title = object["title"]?.textValue ?? "视频笔记"
        content = object["content"]?.textValue ?? "[]"
        aid = object["arc"]?.objectValueForDynamicParsing?["oid"]?.intValueForDynamicParsing
        if case .bool(true) = object["forbid_note_entrance"] { forbidsEditing = true } else { forbidsEditing = false }
    }
    var operations: [DynamicJSONValue] {
        (try? JSONDecoder().decode([DynamicJSONValue].self, from: Data(content.utf8))) ?? []
    }
    var plainText: String {
        operations.compactMap { $0.objectValueForDynamicParsing?["insert"]?.textValue }.joined()
    }
    var canEditAsText: Bool {
        guard let operations = try? JSONDecoder().decode([DynamicJSONValue].self, from: Data(content.utf8)) else { return false }
        return operations.allSatisfy { value in
            guard let object = value.objectValueForDynamicParsing,
                  case .string = object["insert"] else { return false }
            let attributes = object["attributes"]?.objectValueForDynamicParsing ?? [:]
            return attributes.isEmpty
        }
    }
}
