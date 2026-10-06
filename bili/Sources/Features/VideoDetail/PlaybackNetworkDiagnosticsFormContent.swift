import SwiftUI

struct PlaybackNetworkDiagnosticsFormContent: View {
    @ObservedObject var diagnosticsStore: VideoDetailNetworkDiagnosticsRenderStore
    @ObservedObject var relatedStore: VideoDetailRelatedRenderStore
    @ObservedObject var libraryStore: LibraryStore

    let configuration: PlaybackNetworkDiagnosticsFormConfiguration

    var body: some View {
        PiliForm {
            PlaybackNetworkDiagnosticsFormSections(
                diagnosticsStore: diagnosticsStore,
                relatedStore: relatedStore,
                libraryStore: libraryStore,
                configuration: configuration
            )
        }
    }
}
