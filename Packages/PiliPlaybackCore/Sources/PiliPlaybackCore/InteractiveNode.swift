import Foundation

public struct InteractiveNode: Codable, Sendable, Equatable {
    public struct Dimension: Codable, Sendable, Equatable {
        public let width: Double?
        public let height: Double?
        public let rotate: Int?
        enum CodingKeys: String, CodingKey { case width, height, rotate }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            width = c.ruleNumber(.width); height = c.ruleNumber(.height); rotate = c.ruleInt(.rotate)
        }
    }
    public struct Edges: Codable, Sendable, Equatable {
        public let questions: [Question]?
        public let dimension: Dimension?
    }
    public struct Variable: Codable, Sendable, Equatable {
        public let id: String?
        public let idV2: String?
        public let value: Double?
        public let type: Int?
        public let isShow: Bool
        public let name: String?
        public let skipOverwrite: Bool
        public var key: String { InteractiveExpression.canonical(idV2 ?? id ?? "") }
        enum CodingKeys: String, CodingKey { case id, value, type, name; case idV2 = "id_v2", isShow = "is_show", skipOverwrite = "skip_overwrite" }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id)
            idV2 = try c.decodeIfPresent(String.self, forKey: .idV2)
            name = try c.decodeIfPresent(String.self, forKey: .name)
            value = c.ruleNumber(.value); type = c.ruleInt(.type)
            isShow = c.ruleFlag(.isShow); skipOverwrite = c.ruleFlag(.skipOverwrite)
        }
    }
    public struct Question: Codable, Sendable, Equatable {
        public let id: Int?
        public let type: Int?
        public let startTimeR: Int?
        public let duration: Int?
        public let pauseVideo: Bool
        public let title: String?
        public let choices: [Choice]?
        public var countdown: Double? { duration.flatMap { $0 > 0 ? Double($0) / 1_000 : nil } }
        public var isAutomatic: Bool { type == 0 }
        public func isDue(time: Double, duration: Double, ended: Bool) -> Bool {
            if ended { return true }
            guard !isAutomatic, time.isFinite, duration.isFinite, duration > 0, time >= 0 else { return false }
            return duration - time <= max(0, Double(startTimeR ?? 0)) / 1_000
        }
        enum CodingKeys: String, CodingKey { case id, type, duration, title, choices; case startTimeR = "start_time_r", pauseVideo = "pause_video" }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.ruleInt(.id); type = c.ruleInt(.type); startTimeR = c.ruleInt(.startTimeR); duration = c.ruleInt(.duration)
            pauseVideo = c.ruleFlag(.pauseVideo)
            title = try c.decodeIfPresent(String.self, forKey: .title)
            choices = try c.decodeIfPresent([Choice].self, forKey: .choices)
            guard (choices?.count ?? 0) <= 256 else { throw InteractiveRuleError.resourceLimit }
        }
    }
    public struct Choice: Codable, Identifiable, Hashable, Sendable {
        public let id: Int
        public let cid: Int?
        public let option: String?
        public let condition: String?
        public let nativeAction: String?
        public let isDefault: Bool
        public let isHidden: Bool
        public let x: Double?
        public let y: Double?
        public let textAlign: Int?
        public let posX: Double?
        public let posY: Double?
        enum CodingKeys: String, CodingKey {
            case id, cid, option, condition, x, y
            case nativeAction = "native_action", isDefault = "is_default", isHidden = "is_hidden", textAlign = "text_align", posX = "pos_x", posY = "pos_y"
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.ruleInt(.id) ?? 0; cid = c.ruleInt(.cid)
            option = try c.decodeIfPresent(String.self, forKey: .option)
            condition = try c.decodeIfPresent(String.self, forKey: .condition)
            nativeAction = try c.decodeIfPresent(String.self, forKey: .nativeAction)
            isDefault = c.ruleFlag(.isDefault); isHidden = c.ruleFlag(.isHidden)
            x = c.ruleNumber(.x); y = c.ruleNumber(.y); posX = c.ruleNumber(.posX); posY = c.ruleNumber(.posY); textAlign = c.ruleInt(.textAlign)
        }
        /// API pixel y coordinates have their origin at the bottom of the video.
        public func normalizedHotspot(width: Double, height: Double) -> (x: Double, y: Double)? {
            if let x, let y, width.isFinite, height.isFinite, width > 0, height > 0,
               x.isFinite, y.isFinite, (0...width).contains(x), (0...height).contains(y) {
                return (x / width, 1 - y / height)
            }
            if x == nil, y == nil, let posX, let posY, posX.isFinite, posY.isFinite,
               (0...100).contains(posX), (0...100).contains(posY) {
                return (posX / 100, 1 - posY / 100)
            }
            return nil
        }
    }
    public struct Story: Codable, Sendable, Equatable {
        public let cid: Int?
        public let edgeID: Int?
        public let isCurrent: Bool
        enum CodingKeys: String, CodingKey { case cid; case edgeID = "edge_id", isCurrent = "is_current" }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            cid = c.ruleInt(.cid); edgeID = c.ruleInt(.edgeID); isCurrent = c.ruleFlag(.isCurrent)
        }
    }
    public let edgeID: Int?
    public let title: String?
    public let edges: Edges?
    public let hiddenVars: [Variable]
    public let storyList: [Story]
    public let isLeaf: Bool
    public let noBacktracking: Bool
    public let noTutorial: Bool
    public var choices: [Choice] { (edges?.questions ?? []).flatMap { $0.choices ?? [] }.filter { $0.id > 0 } }
    public var currentCID: Int? { storyList.first { $0.isCurrent }?.cid ?? storyList.first { $0.edgeID == edgeID }?.cid }
    enum CodingKeys: String, CodingKey {
        case title, edges
        case edgeID = "edge_id", hiddenVars = "hidden_vars", storyList = "story_list", isLeaf = "is_leaf", noBacktracking = "no_backtracking", noTutorial = "no_tutorial"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        edgeID = c.ruleInt(.edgeID); title = try c.decodeIfPresent(String.self, forKey: .title)
        edges = try c.decodeIfPresent(Edges.self, forKey: .edges)
        hiddenVars = try c.decodeIfPresent([Variable].self, forKey: .hiddenVars) ?? []
        storyList = try c.decodeIfPresent([Story].self, forKey: .storyList) ?? []
        isLeaf = c.ruleFlag(.isLeaf); noBacktracking = c.ruleFlag(.noBacktracking); noTutorial = c.ruleFlag(.noTutorial)
        guard hiddenVars.count <= 512, (edges?.questions?.count ?? 0) <= 64 else { throw InteractiveRuleError.resourceLimit }
    }
}

private extension KeyedDecodingContainer {
    func ruleNumber(_ key: Key) -> Double? {
        let number = (try? decode(Double.self, forKey: key)) ?? (try? decode(String.self, forKey: key)).flatMap(Double.init)
        return number.flatMap { $0.isFinite ? $0 : nil }
    }
    func ruleInt(_ key: Key) -> Int? {
        guard let value = ruleNumber(key), value > Double(Int.min), value < Double(Int.max) else { return nil }
        return Int(value)
    }
    func ruleFlag(_ key: Key) -> Bool {
        (try? decode(Bool.self, forKey: key)) ?? ((ruleNumber(key) ?? 0) != 0)
    }
}
