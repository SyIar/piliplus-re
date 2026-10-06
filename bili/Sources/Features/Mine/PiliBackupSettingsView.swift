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
                    PiliSettingAction(title: "服务器") {
                        TextField("https://…/dav/", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).multilineTextAlignment(.trailing)
                    }
                    PiliSettingAction(title: "用户名") {
                        TextField("用户名", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled().multilineTextAlignment(.trailing)
                    }
                    PiliSettingAction(title: "密码") { SecureField("密码", text: $password).multilineTextAlignment(.trailing) }
                    CCNeoButton("保存连接", variant: .secondary, disabled: isBusy) {
                        do { try PiliWebDAVCredentialStore.save(password); message = "密码已存入钥匙串" }
                        catch { message = error.localizedDescription }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    CCNeoButton("测试连接", variant: .ghost, disabled: isBusy) {
                        await perform { try await client().testConnection(); message = "连接成功" }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    CCNeoButton("备份设置", variant: .primary, disabled: isBusy) {
                        await perform { try await client().backup(PiliSettingsBackup.capture()); message = "设置已备份" }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    CCNeoButton("恢复设置", variant: .secondary, disabled: isBusy) {
                        await perform { let archive = try await client().restore(); confirmRestore(archive) }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("仅备份设置，不含登录凭据、下载和观看进度。文件：PiliPlusSwift/settings.json。")
                        .ccText(font: .cc.sm, color: .cc.mutedForeground)
                    if address.lowercased().hasPrefix("http:") {
                        Text("HTTP 会明文发送账号密码，请优先使用 HTTPS。")
                            .ccText(font: .cc.sm, color: .cc.mutedForeground)
                    }
                }
                Section("本地备份") {
                    CCNeoButton("导出设置", variant: .secondary, icon: PikaIcon.Name.file, disabled: isBusy) {
                        do { exportURL = try PiliSettingsBackup.export(); message = nil }
                        catch { message = error.localizedDescription }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    if let exportURL { ShareLink("分享备份", item: exportURL).frame(maxWidth: .infinity, alignment: .trailing) }
                    CCNeoButton("导入设置", variant: .ghost, icon: PikaIcon.Name.filePlus, disabled: isBusy) { importsFile = true }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    CCNeoButton("撤销上次恢复", variant: .ghost, disabled: isBusy) {
                        PiliAlertSession.present(title: "撤销上次设置恢复？", message: "将恢复为上次导入前的设置。", actions: [
                            PiliAlertButton("取消", role: .cancel),
                            PiliAlertButton("恢复", role: .destructive) {
                                do { try PiliSettingsBackup.rollback(libraryStore: libraryStore); message = "已恢复之前的设置" }
                                catch { message = error.localizedDescription }
                            },
                        ])
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
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
        PiliAlertSession.present(title: "恢复 \(archive.values.count) 项设置？",
                                     message: "备份时间：\(archive.createdAt.formatted())。当前设置会被替换，并在本机保留恢复前的副本。", actions: [
            PiliAlertButton("取消", role: .cancel),
            PiliAlertButton("恢复", role: .destructive) {
                do { try PiliSettingsBackup.apply(archive, libraryStore: libraryStore); message = "设置已恢复" }
                catch { message = error.localizedDescription }
            },
        ])
    }
}
