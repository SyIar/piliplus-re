import Foundation
import PiliPlaybackCore

nonisolated struct PiliOfflineMediaSelection {
    let urls: [OfflineDownloadPart: URL]
    let codec: String?
    let dynamicRange: String

    static func resolve(item: OfflineDownloadItem, data: PlayURLData) throws -> Self {
        if item.effectiveMediaKind == .audio {
            let audios = data.videoListenAudioVariants(cdnPreference: .automatic)
            guard let audio = audios.first(where: { $0.stream.id == item.audioQualityID
                && (item.codec == nil || $0.stream.codecs == item.codec) }) else {
                throw PiliOfflineError.message("当前账号无法取得所选音质，请重新选择可用音质")
            }
            return Self(urls: [.audio: audio.url], codec: audio.stream.codecs, dynamicRange: "sdr")
        }
        let variants = data.playVariants.filter { $0.isPlayable && $0.quality == item.quality }
        guard let variant = variants.first(where: { $0.codec == item.codec }) ?? variants.first,
              let video = variant.videoURL else {
            throw PiliOfflineError.message("当前账号无法取得所选画质，请重新选择可用画质")
        }
        return Self(urls: variant.audioURL.map { [.video: video, .audio: $0] } ?? [.video: video],
                    codec: variant.codec, dynamicRange: variant.dynamicRange.rawValue)
    }
}
