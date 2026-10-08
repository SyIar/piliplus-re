import SwiftUI

/// Shared by the directory and search so each preference has a stable home.
enum PiliSettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case privacy, recommendation, audioVideo, player, appearance, other, webDAV, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .privacy: "\u{9690}\u{79c1}\u{8bbe}\u{7f6e}"
        case .recommendation: "\u{63a8}\u{8350}\u{6d41}\u{8bbe}\u{7f6e}"
        case .audioVideo: "\u{97f3}\u{89c6}\u{9891}\u{8bbe}\u{7f6e}"
        case .player: "\u{64ad}\u{653e}\u{5668}\u{8bbe}\u{7f6e}"
        case .appearance: "\u{5916}\u{89c2}\u{8bbe}\u{7f6e}"
        case .other: "\u{5176}\u{5b83}\u{8bbe}\u{7f6e}"
        case .webDAV: "WebDAV \u{8bbe}\u{7f6e}"
        case .about: "\u{5173}\u{4e8e}"
        }
    }
    var icon: String {
        switch self {
        case .privacy: "hand.raised"
        case .recommendation: "rectangle.stack"
        case .audioVideo: "play.rectangle"
        case .player: "slider.horizontal.3"
        case .appearance: "paintpalette"
        case .other: "gearshape"
        case .webDAV: "externaldrive"
        case .about: "info.circle"
        }
    }
    var subtitle: String {
        switch self {
        case .privacy: "\u{9ed1}\u{540d}\u{5355}\u{4e0e}\u{6d4f}\u{89c8}\u{9690}\u{79c1}"
        case .recommendation: "\u{63a8}\u{8350}\u{6765}\u{6e90}、\u{5237}\u{65b0}\u{4e0e}\u{5185}\u{5bb9}\u{8fc7}\u{6ee4}"
        case .audioVideo: "\u{753b}\u{8d28}、\u{97f3}\u{8d28}\u{4e0e}\u{64ad}\u{653e}\u{7ebf}\u{8def}"
        case .player: "\u{64ad}\u{653e}\u{884c}\u{4e3a}、\u{624b}\u{52bf}\u{4e0e}\u{5168}\u{5c4f}"
        case .appearance: "\u{4e3b}\u{9898}、\u{5b57}\u{53f7}\u{4e0e}\u{9875}\u{9762}\u{5e03}\u{5c40}"
        case .other: "\u{641c}\u{7d22}、\u{6536}\u{85cf}、\u{8bc4}\u{8bba}\u{4e0e}\u{9ad8}\u{7ea7}\u{9009}\u{9879}"
        case .webDAV: "\u{8bbe}\u{7f6e}\u{5907}\u{4efd}\u{4e0e}\u{6062}\u{590d}"
        case .about: "\u{7248}\u{672c}\u{4e0e}\u{5f00}\u{6e90}\u{4fe1}\u{606f}"
        }
    }
    var keywords: String {
        switch self {
        case .privacy: "\u{9ed1}\u{540d}\u{5355} \u{65e0}\u{75d5} \u{6e38}\u{5ba2} \u{591a}\u{8d26}\u{53f7} Cookie"
        case .recommendation: "\u{9996}\u{9875} \u{63a8}\u{8350}\u{6765}\u{6e90} \u{5237}\u{65b0}\u{8ddd}\u{79bb} \u{65f6}\u{957f} \u{64ad}\u{653e}\u{91cf} \u{70b9}\u{8d5e}\u{7387} \u{5173}\u{952e}\u{8bcd} \u{8fc7}\u{6ee4}"
        case .audioVideo: "\u{753b}\u{8d28} \u{97f3}\u{8d28} \u{7f16}\u{7801} \u{786c}\u{89e3} HDR \u{675c}\u{6bd4} CDN \u{7f51}\u{7edc} \u{7ebf}\u{8def} \u{8d85}\u{5206}\u{8fa8}\u{7387} \u{76f4}\u{64ad}"
        case .player: "\u{81ea}\u{52a8}\u{64ad}\u{653e} \u{5386}\u{53f2}\u{540c}\u{6b65} \u{753b}\u{4e2d}\u{753b} \u{624b}\u{52bf} \u{5168}\u{5c4f} \u{65b9}\u{5411} \u{6bd4}\u{4f8b} \u{500d}\u{901f} \u{5f39}\u{5e55} \u{7a7a}\u{964d} \u{8fde}\u{64ad} \u{5b9a}\u{65f6}"
        case .appearance: "\u{4e3b}\u{9898} \u{989c}\u{8272} \u{6df1}\u{8272} \u{5b57}\u{4f53} \u{5b57}\u{53f7} \u{56fe}\u{6807} \u{5e03}\u{5c40} \u{6807}\u{7b7e} \u{56fe}\u{7247} \u{9ad8}\u{5237}\u{65b0}\u{7387} 120Hz"
        case .other: "\u{641c}\u{7d22} \u{70ed}\u{641c} \u{6536}\u{85cf} \u{52a8}\u{6001} \u{8bc4}\u{8bba} \u{63d0}\u{793a} \u{7f13}\u{5b58} \u{8bca}\u{65ad} \u{5b9e}\u{9a8c} \u{7b14}\u{8bb0} \u{8bfe}\u{7a0b}"
        case .webDAV: "\u{5907}\u{4efd} \u{6062}\u{590d} \u{5bfc}\u{5165} \u{5bfc}\u{51fa} \u{540c}\u{6b65}"
        case .about: "\u{7248}\u{672c} \u{5f00}\u{6e90} \u{8bb8}\u{53ef}\u{8bc1} \u{9879}\u{76ee}"
        }
    }
    static func matching(_ query: String) -> [Self] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return allCases.filter { term.isEmpty || ($0.title + $0.keywords).localizedCaseInsensitiveContains(term) }
    }
}

struct PiliSettingsCategoryView: View {
    let category: PiliSettingsCategory
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    var body: some View {
        Group {
            switch category {
            case .privacy: MinePrivacySettingsView(libraryStore: libraryStore)
            case .recommendation:
                PiliForm {
                    MineHomeSettingsSection(libraryStore: libraryStore)
                    Section {
                        NavigationLink("\u{63a8}\u{8350}\u{8fc7}\u{6ee4}") { MineContentFilterSettingsView(scope: .recommendation, libraryStore: libraryStore) }
                    }
                }
            case .audioVideo: MinePlaybackSettingsView(category: .audioVideo, libraryStore: libraryStore)
            case .player: MinePlaybackSettingsView(category: .player, libraryStore: libraryStore)
            case .appearance: MineInterfaceSettingsView(libraryStore: libraryStore)
            case .other: MineOtherSettingsView(libraryStore: libraryStore)
            case .webDAV: PiliBackupSettingsView(libraryStore: libraryStore, embedded: true)
            case .about: PiliForm { MineAboutSection() }
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.category.\(category.rawValue)")
    }
}
