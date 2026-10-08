import SwiftUI
import ChunUI

struct PiliSettingsHomeView: View {
    @ObservedObject var viewModel: MineViewModel
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var libraryStore: LibraryStore
    @State private var confirmsLogout = false

    private var logoutTitle: String {
        libraryStore.multiAccountExperimentEnabled ? "\u{9000}\u{51fa}\u{6240}\u{6709}\u{8d26}\u{53f7}" : "\u{9000}\u{51fa}\u{767b}\u{5f55}"
    }
    var body: some View {
        PiliForm {
            Section {
                NavigationLink { PiliSettingsSearchView(onOpenRoute: { _ in }) } label: {
                    PiliLabel("\u{641c}\u{7d22}\u{8bbe}\u{7f6e}", systemImage: "magnifyingglass")
                }.accessibilityIdentifier("settings.search")
            }
            Section {
                ForEach(PiliSettingsCategory.allCases.filter { $0 != .about }) { category in
                    NavigationLink { PiliSettingsCategoryView(category: category) } label: {
                        SettingsNavigationRow(title: category.title, subtitle: category.subtitle, systemImage: category.icon)
                    }.accessibilityIdentifier("settings.open.\(category.rawValue)")
                }
            }
            Section {
                NavigationLink {
                    MultiAccountExperimentSettingsView(sessionStore: sessionStore, libraryStore: libraryStore, api: viewModel.offlineDownloadAPI)
                } label: { PiliLabel("\u{8d26}\u{53f7}\u{5207}\u{6362}", systemImage: "person.2") }
                if sessionStore.isLoggedIn {
                    Button(role: .destructive) { confirmsLogout = true } label: { Text(logoutTitle) }
                }
            }
            Section {
                NavigationLink { PiliSettingsCategoryView(category: .about) } label: {
                    PiliLabel(PiliSettingsCategory.about.title, systemImage: PiliSettingsCategory.about.icon)
                }
            }
        }
        .navigationTitle("\u{8bbe}\u{7f6e}")
        .navigationBarTitleDisplayMode(.inline)
        .piliAlert("\u{9000}\u{51fa}\u{767b}\u{5f55}？", isPresented: $confirmsLogout) {
            PiliAlertButton("\u{53d6}\u{6d88}", role: .cancel) {}
            PiliAlertButton(logoutTitle, role: .destructive) { viewModel.logout() }
        } message: { "\u{9000}\u{51fa}\u{540e}\u{53ef}\u{5728}\u{4e2a}\u{4eba}\u{4e2d}\u{5fc3}\u{91cd}\u{65b0}\u{767b}\u{5f55}。" }
    }
}
