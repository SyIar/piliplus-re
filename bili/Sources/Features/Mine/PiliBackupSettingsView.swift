import ChunUI
import PiliPlaybackCore
import SwiftUI
import UniformTypeIdentifiers

struct PiliBackupSettingsView: View {
    @ObservedObject var libraryStore: LibraryStore
    @AppStorage("piliplus.webdav.address") private var address = ""
    @AppStorage("piliplus.webdav.username") private var username = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var message: String?
    @State private var exportURL: URL?
    @State private var importsFile = false
    var body: some View {
        NavigationStack {
            PiliForm {
                Section("WebDAV") {
                    TextField("服务器目录 https://.../dav/", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("用户名", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("密码", text: $password)
                    CCNeoButton("保存连接信息", variant: .secondary, disabled: isBusy) {
                        do { try PiliWebDAVCredentialStore.save(password); message = "密码已存入钥匙串" }
                        catch { message = error.localizedDescription }
                    }
                    CCNeoButton("测试连接", variant: .ghost, disabled: isBusy) {
                        await perform { try await client().testConnection(); message = "连接成功" }
                    }
                    CCNeoButton("备份设置到 WebDAV", variant: .primary, disabled: isBusy) {
                        await perform { try await client().backup(PiliSettingsBackup.capture()); message = "设置已备份" }
                    }
                    CCNeoButton("从 WebDAV 恢复", variant: .secondary, disabled: isBusy) {
                        await perform { let archive = try await client().restore(); confirmRestore(archive) }
                    }
                    Text("备份位于指定目录的 PiliPlusSwift/settings.json。备份仅包含设置，登录凭据、下载文件和观看进度保留在本机。")
                        .ccText(font: .cc.sm, color: .cc.mutedForeground)
                    if address.lowercased().hasPrefix("http:") {
                        Text("当前使用 HTTP，账号密码会通过明文连接发送。服务器支持时请使用 HTTPS。")
                            .ccText(font: .cc.sm, color: .cc.mutedForeground)
                    }
                }
                Section("本地备份") {
                    CCNeoButton("导出设置", variant: .secondary, icon: PikaIcon.Name.file, disabled: isBusy) {
                        do { exportURL = try PiliSettingsBackup.export(); message = nil }
                        catch { message = error.localizedDescription }
                    }
                    if let exportURL { ShareLink("保存或分享备份文件", item: exportURL) }
                    CCNeoButton("导入设置", variant: .ghost, icon: PikaIcon.Name.filePlus, disabled: isBusy) { importsFile = true }
                    CCNeoButton("撤销上次恢复", variant: .ghost, disabled: isBusy) {
                        CCAlertCenter.shared.present(title: "撤销上次设置恢复？", message: "将恢复为上次导入前的设置。", actions: [
                            CCAlertAction(title: "取消", role: .secondary),
                            CCAlertAction(title: "恢复", role: .destructive) {
                                do { try PiliSettingsBackup.rollback(libraryStore: libraryStore); message = "已恢复之前的设置" }
                                catch { message = error.localizedDescription }
                            },
                        ])
                    }
                }
                if isBusy { ProgressView("处理中") }
                if let message { Text(message).ccText(font: .cc.sm, color: .cc.mutedForeground) }
            }
            .navigationTitle("设置备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button { AppHelper.shared.dismissSheet() } label: { PikaIcon(PikaIcon.Name.close) }.accessibilityLabel("关闭")
            } }
        }
        .onAppear { do { password = try PiliWebDAVCredentialStore.read() } catch { message = error.localizedDescription } }
        .fileImporter(isPresented: $importsFile, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 10 * 1024 * 1024 else {
                    throw SettingsArchive.ArchiveError.tooLarge
                }
                confirmRestore(try SettingsArchive.decode(Data(contentsOf: url)))
            } catch { message = error.localizedDescription }
        }
    }
    private func client() throws -> PiliWebDAVClient { try PiliWebDAVClient(address: address, username: username, password: password) }
    private func perform(_ operation: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true; message = nil
        defer { isBusy = false }
        do { try await operation() } catch { message = error.localizedDescription }
    }
    private func confirmRestore(_ archive: SettingsArchive) {
        CCAlertCenter.shared.present(title: "恢复 \(archive.values.count) 项设置？",
                                     message: "备份时间：\(archive.createdAt.formatted())。当前设置会被替换，并在本机保留恢复前的副本。", actions: [
            CCAlertAction(title: "取消", role: .secondary),
            CCAlertAction(title: "恢复", role: .destructive) {
                do { try PiliSettingsBackup.apply(archive, libraryStore: libraryStore); message = "设置已恢复" }
                catch { message = error.localizedDescription }
            },
        ])
    }
}
