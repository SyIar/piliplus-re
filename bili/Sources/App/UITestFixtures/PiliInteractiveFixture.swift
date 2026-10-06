import SwiftUI

/// Exercises the production controller and choice surface without API accounts.
struct PiliInteractiveFixture: View {
    @StateObject private var controller = PiliInteractiveController()
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.05, green: 0.12, blue: 0.28), .black],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "sparkles").font(.system(size: 110)).foregroundStyle(.white.opacity(0.12))
                    PiliInteractiveChoicesView(controller: controller)
                }
                .frame(height: 340).clipShape(RoundedRectangle(cornerRadius: 24))
                Text(controller.edge?.title ?? "加载剧情").font(.title3.bold())
                    .accessibilityIdentifier("ui.interactive.nodeTitle")
                Text("剧情路径 · \(controller.history.count) 段")
                    .foregroundStyle(.secondary)
                Button("回到起点") {
                    if let root = controller.history.first { controller.revisit(root) }
                }
                .buttonStyle(.glass)
                .disabled(controller.isLoading || controller.isBacktrackingRestricted || controller.history.count < 2)
                .accessibilityIdentifier("ui.interactive.revisit")
                if controller.isBacktrackingRestricted {
                    Label("作者已限制本段剧情回溯", systemImage: "lock").font(.caption)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("互动故事").navigationBarTitleDisplayMode(.inline)
        }
        .task {
            AppOrientationLock.restorePortrait()
            controller.start(context: "fixture", saveKey: "piliplus.fixture.interactive", graphVersion: 1, cid: 10,
                             loader: { id in
                let json: String
                switch id {
                case nil, 1: json = Self.root
                case 2: json = Self.hotspots
                case 4: json = Self.ending
                default: throw BiliAPIError.emptyData
                }
                return try JSONDecoder().decode(PiliInteractiveEdge.self, from: Data(json.utf8))
            }, navigator: { _, _ in })
        }
        // Fixture clips finish immediately; branch state and UI remain production code.
        .onChange(of: controller.history.last?.id) { _, _ in _ = controller.handlePlaybackEnded() }
    }
    private static let root = #"""
    {
      "edge_id":1,"title":"一场新的冒险",
      "hidden_vars":[{"id_v2":"$score","name":"积分","value":0,"is_show":1}],
      "edges":{"questions":[{"type":1,"title":"旅程从这里开始","pause_video":1,"choices":[
        {"id":2,"cid":20,"option":"推开蓝色的门","native_action":"$score=$score+1","is_default":1},
        {"id":3,"cid":30,"option":"尚未解锁的捷径","condition":"$score > 10"}
      ]}]}
    }
    """#
    private static let hotspots = #"""
    {
      "edge_id":2,"title":"星光之间",
      "hidden_vars":[{"id_v2":"$score","name":"积分","value":0,"is_show":1}],
      "edges":{"dimension":{"width":1920,"height":1080},"questions":[
        {"type":2,"pause_video":1,"choices":[
          {"id":4,"cid":40,"option":"走向星光","x":960,"y":620,"condition":"$score == 1"}
        ]}
      ]}
    }
    """#
    private static let ending = #"{"edge_id":4,"title":"故事的终点","is_leaf":1,"no_backtracking":1}"#
}
