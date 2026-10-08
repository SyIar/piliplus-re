import SwiftUI

struct DynamicView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var showsComposer = false
    @State private var category = PiliDynamicCategory.all

    private var categoryPicker: some View {
        Picker("\u{52a8}\u{6001}\u{5206}\u{7c7b}", selection: $category) {
            ForEach(PiliDynamicCategory.allCases) { Text($0.title).tag($0) }
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    categoryPicker.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                } else { categoryPicker.pickerStyle(.segmented) }
            }.padding(.horizontal).padding(.vertical, 8)
            DynamicContentRoot(api: dependencies.api, libraryStore: libraryStore,
                sessionStore: dependencies.sessionStore, category: category).id(category)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsComposer = true } label: { PiliIcon(systemName: "square.and.pencil") }
                    .accessibilityLabel("\u{53d1}\u{5e03}\u{52a8}\u{6001}").accessibilityIdentifier("pili.dynamic.compose")
            }
        }
        .piliSheet(isPresented: $showsComposer) {
            PiliDynamicComposer(api: dependencies.api) { NotificationCenter.default.post(name: .piliDynamicChanged, object: nil) }
        }
    }
}

private struct DynamicContentRoot: View {
    let api: BiliAPIClient
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var sessionStore: SessionStore
    let category: PiliDynamicCategory
    @StateObject private var holder = DynamicViewModelHolder()
    @StateObject private var pullRefreshSettings = PullRefreshRuntimeSettingsStore()

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                DynamicFeedScreenContent(
                    api: api,
                    viewModel: viewModel,
                    isLoggedIn: sessionStore.isLoggedIn,
                    pullRefreshTriggerDistance: CGFloat(pullRefreshSettings.triggerDistance)
                )
            } else {
                DynamicInitialFeedContent(isLoggedIn: sessionStore.isLoggedIn)
                    .task {
                        holder.configure(
                            api: api,
                            libraryStore: libraryStore,
                            sessionStore: sessionStore, category: category
                        )
                    }
            }
        }
        .task {
            pullRefreshSettings.bind(libraryStore)
        }
        .onChange(of: DynamicFeedAccountContext(
            mainCredentialVersion: sessionStore.playbackCredentialVersion,
            dynamicFeedCredentialVersion: sessionStore.dynamicFeedAccountCredentialVersion,
            multiAccountExperimentEnabled: libraryStore.multiAccountExperimentEnabled
        )) { _, _ in
            holder.reconfigure(
                api: api,
                libraryStore: libraryStore,
                sessionStore: sessionStore, category: category
            )
        }
    }
}

private struct DynamicFeedAccountContext: Equatable {
    let mainCredentialVersion: Int
    let dynamicFeedCredentialVersion: Int
    let multiAccountExperimentEnabled: Bool
}

extension View {
    @ViewBuilder
    func dynamicLoadMoreTask<ID: Equatable>(
        if condition: Bool,
        id: ID,
        action: @escaping () async -> Void
    ) -> some View {
        if condition {
            task(id: id) {
                await action()
            }
        } else {
            self
        }
    }
}
