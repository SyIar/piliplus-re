import SwiftUI
import ChunUI

struct PiliLivePlaybackSettingsView: View {
    @ObservedObject var libraryStore: LibraryStore
    @State private var draft = PiliLivePlaybackPreferences()
    @State private var error: String?
    @PiliDismiss private var dismiss
    var body: some View {
        PiliForm {
            Section("默认画质") {
                quality("Wi-Fi 等网络", selection: $draft.quality)
                quality("蜂窝网络", selection: $draft.cellularQuality)
            }
            Section {
                PiliSettingAction(title: "CDN") {
                    TextField("默认", text: $draft.cdnHost).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
            } header: { Text("直播线路") }
              footer: { Text("留空使用默认线路；失败时尝试备用线路。重新打开直播后生效。") }
            if let error { Text(error).foregroundStyle(Color.cc.destructive) }
        }
        .navigationTitle("直播设置").navigationBarTitleDisplayMode(.inline)
        .onAppear { draft = libraryStore.livePlaybackPreferences }
        .toolbar { ToolbarItem(placement: .confirmationAction) {
            Button("保存") {
                do { draft.cdnHost = draft.cdnHost.trimmingCharacters(in: .whitespacesAndNewlines); try libraryStore.setLivePlaybackPreferences(draft); dismiss() }
                catch { self.error = error.localizedDescription }
            }
        } }
    }
    private func quality(_ title: String, selection: Binding<Int>) -> some View {
        PiliSettingPicker(title, selection: selection) {
            ForEach(PiliLivePlaybackPreferences.qualities, id: \.self) { value in Text(LiveStreamQuality.defaultTitle(for: value)).tag(value) }
        }
    }
}
