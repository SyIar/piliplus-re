import SwiftUI
import ChunUI

struct MultiAccountExperimentSettingsView: View {
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var libraryStore: LibraryStore
    let api: BiliAPIClient

    @State private var isShowingWebLogin = false
    @State private var isAddingAccount = false
    @State private var errorMessage: String?

    var body: some View {
        PiliForm {
            if libraryStore.multiAccountExperimentEnabled {
                accountsSection
                purposeSection
                addAccountSection
            } else {
                PiliUnavailableView(
                    "实验尚未开启",
                    systemImage: "person.2.badge.gearshape",
                    description: Text("请先在隐私设置中打开“多账号用途分配实验”。")
                )
            }
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
        .piliSheet(isPresented: $isShowingWebLogin) {
            BiliWebLoginView(usesIsolatedSession: true) { cookies in
                addAccount(cookies)
            }
        }
        .piliAlert(
            "账号操作失败",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            PiliAlertButton("好", role: .cancel) {}
        } message: { errorMessage ?? "未知错误" }
    }

    private var purposeSection: some View {
        Section {
            if sessionStore.accounts.isEmpty {
                PiliUnavailableView(
                    "还没有账号",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("添加账号后才能分配用途。")
                )
            } else {
                Picker(
                    selection: Binding(
                        get: { sessionStore.mainAccountMID ?? sessionStore.accounts[0].mid },
                        set: { value in selectMainAccount(value) }
                    )
                ) {
                    ForEach(sessionStore.accounts) { account in
                        Text(account.displayName).tag(account.mid)
                    }
                } label: {
                    MineSettingsLabel("主账号", systemImage: "person.crop.circle.fill")
                }
                .pickerStyle(.menu)

                Picker(
                    selection: Binding(
                        get: {
                            sessionStore.playbackAccountMID
                                ?? sessionStore.mainAccountMID
                                ?? sessionStore.accounts[0].mid
                        },
                        set: { value in selectPlaybackAccount(value) }
                    )
                ) {
                    ForEach(sessionStore.accounts) { account in
                        Text(account.displayName).tag(account.mid)
                    }
                } label: {
                    MineSettingsLabel("视频取流账号", systemImage: "play.rectangle.on.rectangle")
                }
                .pickerStyle(.menu)

                Picker(
                    selection: Binding(
                        get: {
                            sessionStore.dynamicFeedAccountMID
                                ?? sessionStore.mainAccountMID
                                ?? sessionStore.accounts[0].mid
                        },
                        set: { value in selectDynamicFeedAccount(value) }
                    )
                ) {
                    ForEach(sessionStore.accounts) { account in
                        Text(account.displayName).tag(account.mid)
                    }
                } label: {
                    MineSettingsLabel("动态页取流账号", systemImage: "sparkles.rectangle.stack")
                }
                .pickerStyle(.menu)

                Picker(
                    selection: Binding(
                        get: {
                            sessionStore.interactionAccountMID
                                ?? sessionStore.mainAccountMID
                                ?? sessionStore.accounts[0].mid
                        },
                        set: { value in selectInteractionAccount(value) }
                    )
                ) {
                    ForEach(sessionStore.accounts) { account in
                        Text(account.displayName).tag(account.mid)
                    }
                } label: {
                    MineSettingsLabel("点赞、投币与收藏", systemImage: "hand.thumbsup.fill")
                }
                .pickerStyle(.menu)

                Picker("评论读取", selection: Binding(get: { sessionStore.commentReadPolicy }, set: { policy in
                    do { try sessionStore.setCommentReadPolicy(policy, mid: sessionStore.commentReadAccountMID ?? sessionStore.mainAccountMID) }
                    catch { errorMessage = error.localizedDescription }
                })) {
                    ForEach(CommentReadAccountPolicy.allCases) { Text($0.title).tag($0) }
                }
                if sessionStore.commentReadPolicy == .account {
                    Picker("评论读取账号", selection: Binding(get: { sessionStore.commentReadAccountMID ?? sessionStore.accounts[0].mid }, set: { mid in
                        do { try sessionStore.setCommentReadPolicy(.account, mid: mid) }
                        catch { errorMessage = error.localizedDescription }
                    })) { ForEach(sessionStore.accounts) { Text($0.displayName).tag($0.mid) } }
                }
                Picker(
                    selection: Binding(
                        get: { sessionStore.historyAccountPolicy },
                        set: { value in selectHistoryPolicy(value) }
                    )
                ) {
                    ForEach(WatchHistoryAccountPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                } label: {
                    MineSettingsLabel("观看记录", systemImage: "clock.arrow.circlepath")
                }
                .pickerStyle(.menu)
            }
        } header: {
            Text("账号用途")
        } footer: {
            Text("主账号负责首页、消息和关注。评论读取可单独分配或匿名访问；发评论、点赞、删除仍使用互动账号。两者不同时，不将读取账号的赞/踩标记作为互动账号状态。视频取流账号负责普通视频、番剧和画面预览；动态页取流账号负责动态列表和顶部关注 UP；互动账号负责点赞、投币、收藏及收藏夹。直播仍使用主账号。选择“不上传记录”后不会上传新进度，但仍可查看主账号已有历史。")
        }
    }

    private var accountsSection: some View {
        Section("已保存账号") {
            ForEach(sessionStore.accounts) { account in
                MultiAccountExperimentAccountRow(
                    account: account,
                    canDelete: sessionStore.mainAccountMID != account.mid,
                    onDelete: { removeAccount(account.mid) }
                )
            }
        }
    }

    private var addAccountSection: some View {
        Section {
            Button {
                isShowingWebLogin = true
            } label: {
                MineSettingsLabel("添加账号（网页登录）", systemImage: "person.crop.circle.badge.plus")
            }
            .disabled(isAddingAccount)

            if isAddingAccount {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在验证账号")
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("新增账号使用独立的临时网页登录环境，不会自动带入当前主账号的 Cookie。首版暂不提供第二账号的短信和扫码登录。")
        }
    }

    private func selectMainAccount(_ mid: Int) {
        do {
            try sessionStore.selectMainAccount(mid: mid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectPlaybackAccount(_ mid: Int) {
        do {
            try sessionStore.selectPlaybackAccount(mid: mid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectDynamicFeedAccount(_ mid: Int) {
        do {
            try sessionStore.selectDynamicFeedAccount(mid: mid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectInteractionAccount(_ mid: Int) {
        do {
            try sessionStore.selectInteractionAccount(mid: mid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectHistoryPolicy(_ policy: WatchHistoryAccountPolicy) {
        do {
            try sessionStore.setHistoryAccountPolicy(policy)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeAccount(_ mid: Int) {
        do {
            try sessionStore.removeAccount(mid: mid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addAccount(_ cookies: [HTTPCookie]) {
        do {
            let account = try sessionStore.saveAdditionalAccount(cookies)
            guard let credentials = sessionStore.credentialSnapshot(forAccountMID: account.mid) else {
                throw MultiAccountSessionError.accountNotFound
            }
            isAddingAccount = true
            Task {
                do {
                    let user = try await api.fetchNavUser(cookieHeader: credentials.cookieHeader)
                    sessionStore.updateAccountUser(mid: account.mid, user: user)
                } catch {
                    errorMessage = "账号已保存，但资料验证失败：\(error.localizedDescription)"
                }
                isAddingAccount = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MultiAccountExperimentAccountRow: View {
    let account: BiliAccountSummary
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AvatarRemoteImage(urlString: account.face, pixelSize: 96) {
                Circle()
                    .fill(.quaternary)
                    .overlay {
                        PiliIcon(systemName: "person.fill")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 42, height: 42)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(account.displayName)
                    .appTypography(.settingsRow, fallback: .body)
                    .lineLimit(1)

                Text("UID \(account.mid)")
                    .appTypography(.settingsSubtitle, fallback: .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Menu {
                Button(role: .destructive, action: onDelete) {
                    PiliLabel("删除账号", systemImage: "trash")
                }
                .disabled(!canDelete)
            } label: {
                PiliIcon(systemName: "ellipsis.circle")
                    .piliFont(.baseBold)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .accessibilityLabel("\(account.displayName)账号管理")
        }
        .padding(.vertical, 2)
    }
}
