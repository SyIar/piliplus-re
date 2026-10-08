import ChunUI
import PiliPlaybackCore
import SwiftUI
import UniformTypeIdentifiers

struct PiliBackupSettingsView: View {
    @ObservedObject var libraryStore: LibraryStore
    var embedded = false
    @AppStorage("piliplus.webdav.address") private var address = ""
    @AppStorage("piliplus.webdav.username") private var username = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var message: String?
    @State private var exportURL: URL?
    @State private var importsFile = false
    var body: some View {
        Group {
            if embedded { settingsContent }
            else { NavigationStack { settingsContent } }
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
    private var settingsContent: some View {
            PiliForm {
                Section("WebDAV") {
                    PiliSettingAction(title: "\u{670d}\u{52a1}\u{5668}") {
                        TextField("https://…/dav/", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).multilineTextAlignment(.trailing)
                    }
                    PiliSettingAction(title: "\u{7528}\u{6237}\u{540d}") {
                        TextField("\u{7528}\u{6237}\u{540d}", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled().multilineTextAlignment(.trailing)
                    }
                    PiliSettingAction(title: "\u{5bc6}\u{7801}") { SecureField("\u{5bc6}\u{7801}", text: $password).multilineTextAlignment(.trailing) }
                    CCNeoButton("\u{4fdd}\u{5b58}\u{8fde}\u{63a5}", variant: .secondary, disabled: isBusy) {
                        do { try PiliWebDAVCredentialStore.save(password); message = "\u{5bc6}\u{7801}\u{5df2}\u{5b58}\u{5165}\u{94a5}\u{5319}\u{4e32}" }
                        catch { message = error.localizedDescription }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    CCNeoButton("\u{6d4b}\u{8bd5}\u{8fde}\u{63a5}", variant: .ghost, disabled: isBusy) {
                        await perform { try await client().testConnection(); message = "\u{8fde}\u{63a5}\u{6210}\u{529f}" }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    CCNeoButton("\u{5907}\u{4efd}\u{8bbe}\u{7f6e}", variant: .primary, disabled: isBusy) {
                        await perform { try await client().backup(PiliSettingsBackup.capture()); message = "\u{8bbe}\u{7f6e}\u{5df2}\u{5907}\u{4efd}" }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    CCNeoButton("\u{6062}\u{590d}\u{8bbe}\u{7f6e}", variant: .secondary, disabled: isBusy) {
                        await perform { let archive = try await client().restore(); confirmRestore(archive) }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("\u{4ec5}\u{5907}\u{4efd}\u{8bbe}\u{7f6e}，\u{4e0d}\u{542b}\u{767b}\u{5f55}\u{51ed}\u{636e}、\u{4e0b}\u{8f7d}\u{548c}\u{89c2}\u{770b}\u{8fdb}\u{5ea6}。\u{6587}\u{4ef6}：PiliPlusSwift/settings.json。")
                        .ccText(font: .cc.sm, color: .cc.mutedForeground)
                    if address.lowercased().hasPrefix("http:") {
                        Text("HTTP \u{4f1a}\u{660e}\u{6587}\u{53d1}\u{9001}\u{8d26}\u{53f7}\u{5bc6}\u{7801}，\u{8bf7}\u{4f18}\u{5148}\u{4f7f}\u{7528} HTTPS。")
                            .ccText(font: .cc.sm, color: .cc.mutedForeground)
                    }
                }
                Section("\u{672c}\u{5730}\u{5907}\u{4efd}") {
                    CCNeoButton("\u{5bfc}\u{51fa}\u{8bbe}\u{7f6e}", variant: .secondary, icon: PikaIcon.Name.file, disabled: isBusy) {
                        do { exportURL = try PiliSettingsBackup.export(); message = nil }
                        catch { message = error.localizedDescription }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    if let exportURL { ShareLink("\u{5206}\u{4eab}\u{5907}\u{4efd}", item: exportURL).frame(maxWidth: .infinity, alignment: .trailing) }
                    CCNeoButton("\u{5bfc}\u{5165}\u{8bbe}\u{7f6e}", variant: .ghost, icon: PikaIcon.Name.filePlus, disabled: isBusy) { importsFile = true }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    CCNeoButton("\u{64a4}\u{9500}\u{4e0a}\u{6b21}\u{6062}\u{590d}", variant: .ghost, disabled: isBusy) {
                        PiliAlertSession.present(title: "\u{64a4}\u{9500}\u{4e0a}\u{6b21}\u{8bbe}\u{7f6e}\u{6062}\u{590d}？", message: "\u{5c06}\u{6062}\u{590d}\u{4e3a}\u{4e0a}\u{6b21}\u{5bfc}\u{5165}\u{524d}\u{7684}\u{8bbe}\u{7f6e}。", actions: [
                            PiliAlertButton("\u{53d6}\u{6d88}", role: .cancel),
                            PiliAlertButton("\u{6062}\u{590d}", role: .destructive) {
                                do { try PiliSettingsBackup.rollback(libraryStore: libraryStore); message = "\u{5df2}\u{6062}\u{590d}\u{4e4b}\u{524d}\u{7684}\u{8bbe}\u{7f6e}" }
                                catch { message = error.localizedDescription }
                            },
                        ])
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if isBusy { ProgressView("\u{5904}\u{7406}\u{4e2d}") }
                if let message { Text(message).ccText(font: .cc.sm, color: .cc.mutedForeground) }
            }
            .navigationTitle("\u{8bbe}\u{7f6e}\u{5907}\u{4efd}")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { if !embedded { ToolbarItem(placement: .topBarTrailing) {
                Button { AppHelper.shared.dismissSheet() } label: { PikaIcon(PikaIcon.Name.close) }.accessibilityLabel("\u{5173}\u{95ed}")
            } } }
    }
    private func client() throws -> PiliWebDAVClient { try PiliWebDAVClient(address: address, username: username, password: password) }
    private func perform(_ operation: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true; message = nil
        defer { isBusy = false }
        do { try await operation() } catch { message = error.localizedDescription }
    }
    private func confirmRestore(_ archive: SettingsArchive) {
        PiliAlertSession.present(title: "\u{6062}\u{590d} \(archive.values.count) \u{9879}\u{8bbe}\u{7f6e}？",
                                     message: "\u{5907}\u{4efd}\u{65f6}\u{95f4}：\(archive.createdAt.formatted())。\u{5f53}\u{524d}\u{8bbe}\u{7f6e}\u{4f1a}\u{88ab}\u{66ff}\u{6362}，\u{5e76}\u{5728}\u{672c}\u{673a}\u{4fdd}\u{7559}\u{6062}\u{590d}\u{524d}\u{7684}\u{526f}\u{672c}。", actions: [
            PiliAlertButton("\u{53d6}\u{6d88}", role: .cancel),
            PiliAlertButton("\u{6062}\u{590d}", role: .destructive) {
                do { try PiliSettingsBackup.apply(archive, libraryStore: libraryStore); message = "\u{8bbe}\u{7f6e}\u{5df2}\u{6062}\u{590d}" }
                catch { message = error.localizedDescription }
            },
        ])
    }
}
