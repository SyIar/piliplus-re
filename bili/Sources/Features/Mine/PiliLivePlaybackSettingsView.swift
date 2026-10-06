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
                quality("Wi-Fi／其他网络", selection: $draft.quality)
                quality("蜂窝网络", selection: $draft.cellularQuality)
            }
            Section {
                TextField("使用平台默认 CDN", text: $draft.cdnHost).textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: { Text("直播 CDN 主机名") }
              footer: { Text("留空使用平台线路。指定线路失败后会尝试平台备用线路。新设置在下一次打开或重新加载直播时生效。") }
            if let error { Text(error).foregroundStyle(Color.cc.destructive) }
        }
        .navigationTitle("直播播放偏好").navigationBarTitleDisplayMode(.inline)
        .onAppear { draft = libraryStore.livePlaybackPreferences }
        .toolbar { ToolbarItem(placement: .confirmationAction) {
            Button("保存") {
                do { draft.cdnHost = draft.cdnHost.trimmingCharacters(in: .whitespacesAndNewlines); try libraryStore.setLivePlaybackPreferences(draft); dismiss() }
                catch { self.error = error.localizedDescription }
            }
        } }
    }
    private func quality(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(PiliLivePlaybackPreferences.qualities, id: \.self) { value in Text(LiveStreamQuality.defaultTitle(for: value)).tag(value) }
        }
    }
}
