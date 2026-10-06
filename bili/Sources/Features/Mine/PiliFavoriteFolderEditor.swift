import ChunUI
import ImageIO
import PhotosUI
import SwiftUI

struct PiliFavoriteFolderEditor: View {
    let api: BiliAPIClient
    let folder: FavoriteFolder?
    let credentialVersion: Int
    let onSaved: () -> Void
    @PiliDismiss private var dismiss
    @State private var loaded = false
    @State private var busy = false
    @State private var loadingPhoto = false
    @State private var title = ""
    @State private var intro = ""
    @State private var isPublic = false
    @State private var cover = ""
    @State private var isDefault = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var jpeg: Data?
    @State private var error: String?

    var body: some View {
        PiliForm {
            if !loaded, error == nil { ProgressView("读取收藏夹") }
            if !loaded, error != nil { Button("重新读取") { Task { await prepare() } } }
            if let error { Text(error).ccText(font: .cc.sm, color: .cc.destructive) }
            Section("基本信息") {
                TextField("收藏夹名称", text: $title).disabled(isDefault)
                if !isDefault {
                    TextField("简介", text: $intro, axis: .vertical).lineLimit(3...6)
                    Text("名称最多 20 字，简介最多 200 字").ccText(font: .cc.sm, color: .cc.mutedForeground)
                }
                Toggle("公开收藏夹", isOn: $isPublic)
            }
            if !isDefault {
                Section("封面") {
                    if let jpeg, let image = UIImage(data: jpeg) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180)
                    } else if let url = URL(string: cover), !cover.isEmpty {
                        AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }.frame(maxHeight: 180)
                    }
                    PhotosPicker("选择封面图片", selection: $selectedPhoto, matching: .images)
                    if jpeg != nil || !cover.isEmpty { Button("移除封面", role: .destructive) { jpeg = nil; cover = ""; selectedPhoto = nil } }
                }
            }
        }
        .tint(.cc.primary)
        .disabled(busy)
        .navigationTitle(folder == nil ? "新建收藏夹" : "编辑收藏夹")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
            ToolbarItem(placement: .confirmationAction) { Button(busy ? "保存中…" : "保存") { save() }.disabled(!loaded || busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loadingPhoto || title.count > 20 || intro.count > 200) }
        }
        .task { await prepare() }
        .task(id: selectedPhoto) {
            guard let photo = selectedPhoto else { loadingPhoto = false; return }
            loadingPhoto = true
            defer { if selectedPhoto == photo { loadingPhoto = false } }
            do {
                guard let data = try await photo.loadTransferable(type: Data.self), data.count <= 25 * 1024 * 1024,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 1600,
                        kCGImageSourceCreateThumbnailWithTransform: true
                      ] as CFDictionary), let value = UIImage(cgImage: cg).jpegData(compressionQuality: 0.86) else {
                    throw PiliOfflineError.message("无法读取图片，请选择小于 25 MB 的照片")
                }
                guard !Task.isCancelled else { return }
                jpeg = value
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func prepare() async {
        guard !loaded else { return }
        error = nil
        do {
            guard api.requestSnapshot(purpose: .interaction).playbackCredentialVersion == credentialVersion else {
                throw PiliOfflineError.message("账号已切换，请重新打开编辑器")
            }
            if let folder {
                let full = try await api.fetchPiliFavoriteFolder(id: folder.id)
                guard !Task.isCancelled, api.requestSnapshot(purpose: .interaction).playbackCredentialVersion == credentialVersion else {
                    throw PiliOfflineError.message("账号已切换，请重新打开编辑器")
                }
                title = full.title ?? ""; intro = full.intro ?? ""; isPublic = full.isPiliPublic
                cover = full.cover ?? ""; isDefault = full.isPiliDefault
            }
            loaded = true
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func save() {
        guard !busy else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                if let jpeg {
                    cover = try await api.uploadPiliFavoriteCover(jpeg, credentialVersion: credentialVersion)
                    self.jpeg = nil
                }
                try await api.savePiliFavoriteFolder(id: folder?.id, title: title, intro: intro,
                                                     isPublic: isPublic, cover: cover, credentialVersion: credentialVersion)
                onSaved(); dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
