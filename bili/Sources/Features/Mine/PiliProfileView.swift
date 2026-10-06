import ChunUI
import ImageIO
import PhotosUI
import SwiftUI

struct PiliProfileView: View {
    let api: BiliAPIClient
    let identity: PiliAccountIdentity
    @ObservedObject private var session: SessionStore
    @State private var profile: PiliOwnProfile?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var editing: PiliProfileField?
    @State private var photo: PhotosPickerItem?
    @State private var loadingPhoto = false
    @State private var cropPhoto: AvatarPhoto?
    private struct AvatarPhoto: Identifiable { let id = UUID(); let image: UIImage }
    init(api: BiliAPIClient) {
        self.api = api; identity = PiliAccountIdentity(api.requestSnapshot(purpose: .main))
        _session = ObservedObject(wrappedValue: api.sessionStore)
    }
    private var isCurrent: Bool { identity.matches(api.requestSnapshot(purpose: .main)) }
    private var canEditFields: Bool { api.requestSnapshot(purpose: .main).appAccessKey?.isEmpty == false }
    var body: some View {
        NavigationStack {
            PiliForm {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Color.cc.destructive)
                    if isCurrent { Button("重新读取") { Task { await load() } } }
                }
                if loading { ProgressView("读取个人资料") }
                if let profile {
                    Section {
                        HStack {
                            AvatarRemoteImage(urlString: profile.face, pixelSize: 160) {
                                PiliIcon(systemName: "person.crop.circle").resizable()
                            }.frame(width: 64, height: 64).clipShape(Circle())
                            Spacer()
                            PhotosPicker("更换头像", selection: $photo, matching: .images).disabled(loadingPhoto || !isCurrent)
                        }
                        if loadingPhoto { ProgressView("读取照片") }
                        LabeledContent("UID", value: String(profile.mid)).textSelection(.enabled)
                    }
                    Section("基本资料") {
                        fieldRow(.uname, value: profile.name)
                        fieldRow(.sign, value: profile.sign.isEmpty ? "未设置" : profile.sign)
                        fieldRow(.sex, value: [0: "保密", 1: "男", 2: "女"][profile.sex ?? 0] ?? "未设置")
                        fieldRow(.birthday, value: profile.birthday ?? "未设置")
                    }.disabled(!canEditFields || !isCurrent)
                    if !canEditFields {
                        Section { Text("当前登录方式支持修改头像；修改其他资料需要在登录页使用 App 扫码或短信登录。")
                            .ccText(font: .cc.sm, color: .cc.mutedForeground) }
                    }
                    Section {
                        Link("头像挂件", destination: URL(string: "https://www.bilibili.com/h5/mall/pendant/home")!)
                    }
                }
            }
            .navigationTitle("个人资料")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { AppHelper.shared.dismissSheet() } } }
            .task { await load() }
            .onChange(of: session.playbackCredentialVersion) { _, _ in
                if !isCurrent { editing = nil; photo = nil; cropPhoto = nil; profile = nil; errorMessage = "账号已切换，请重新打开个人资料" }
            }
            .task(id: photo) {
                guard let selected = photo else { loadingPhoto = false; return }
                loadingPhoto = true
                defer { if photo == selected { loadingPhoto = false } }
                do {
                    guard let bytes = try await selected.loadTransferable(type: Data.self), bytes.count <= 25 * 1024 * 1024,
                          let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1600,
                            kCGImageSourceCreateThumbnailWithTransform: true
                          ] as CFDictionary) else { throw PiliOfflineError.message("请选择小于 25 MB 的有效照片") }
                    guard !Task.isCancelled, isCurrent else { return }
                    cropPhoto = AvatarPhoto(image: UIImage(cgImage: image))
                } catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
            }
            .piliSheet(item: $editing) { field in
                if let profile {
                    NavigationStack { PiliProfileFieldEditor(api: api, identity: identity, profile: profile, field: field) { changed() } }
                }
            }
            .piliSheet(item: $cropPhoto, onDismiss: { photo = nil }) { image in
                NavigationStack { PiliAvatarCropView(api: api, identity: identity, image: image.image) { changed() } }
            }
        }
    }
    private func fieldRow(_ field: PiliProfileField, value: String) -> some View {
        Button { editing = field } label: {
            HStack {
                Text(field.title).foregroundStyle(Color.cc.foreground)
                Spacer()
                Text(value).foregroundStyle(Color.cc.mutedForeground).lineLimit(2).multilineTextAlignment(.trailing)
                PiliIcon(systemName: "chevron.right").piliFont(.sm).foregroundStyle(Color.cc.mutedForeground)
            }
        }
    }
    private func load() async {
        guard !loading else { return }
        loading = true; errorMessage = nil
        defer { loading = false }
        do {
            let value = try await api.fetchPiliOwnProfile(identity: identity)
            guard !Task.isCancelled, isCurrent else { return }
            profile = value
        } catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
    }
    private func changed() {
        Task {
            await load()
            if let nav = try? await api.fetchNavUser(), isCurrent { session.updateUser(nav) }
        }
    }
}

private struct PiliProfileFieldEditor: View {
    let api: BiliAPIClient
    let identity: PiliAccountIdentity
    let profile: PiliOwnProfile
    let field: PiliProfileField
    let onSaved: () -> Void
    @PiliDismiss private var dismiss
    @State private var value = ""
    @State private var birthday = Date()
    @State private var busy = false
    @State private var confirmName = false
    @State private var errorMessage: String?
    private var formatter: DateFormatter {
        let value = DateFormatter(); value.locale = Locale(identifier: "en_US_POSIX")
        value.calendar = Calendar(identifier: .gregorian); value.dateFormat = "yyyy-MM-dd"
        return value
    }
    private var currentValue: String {
        switch field {
        case .uname: profile.name
        case .sign: profile.sign
        case .sex: String(profile.sex ?? 0)
        case .birthday: profile.birthday ?? ""
        }
    }
    private var submittedValue: String { field == .birthday ? formatter.string(from: birthday) : value }
    private var canSave: Bool {
        guard !busy, submittedValue != currentValue else { return false }
        switch field {
        case .uname: return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= 16 && (profile.coins.map { $0 >= 6 } ?? true)
        case .sign: return value.count <= 70
        case .sex, .birthday: return true
        }
    }
    var body: some View {
        PiliForm {
            if let errorMessage { Text(errorMessage).foregroundStyle(Color.cc.destructive) }
            switch field {
            case .uname:
                TextField("昵称", text: $value).autocorrectionDisabled()
                Text("\(value.count)/16 字").foregroundStyle(Color.cc.mutedForeground)
                Text("修改昵称将消耗 6 硬币。")
                if let coins = profile.coins { Text("当前硬币：\(coins.formatted())") }
            case .sign:
                TextField("个性签名", text: $value, axis: .vertical).lineLimit(4...8)
                Text("\(value.count)/70 字").foregroundStyle(Color.cc.mutedForeground)
            case .sex:
                Picker("性别", selection: $value) { Text("保密").tag("0"); Text("男").tag("1"); Text("女").tag("2") }
            case .birthday:
                DatePicker("生日", selection: $birthday, in: ...Date(), displayedComponents: .date).datePickerStyle(.graphical)
            }
        }
        .disabled(busy)
        .navigationTitle("修改\(field.title)")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
            ToolbarItem(placement: .confirmationAction) {
                Button(busy ? "保存中…" : "保存") { if field == .uname { confirmName = true } else { save() } }.disabled(!canSave)
            }
        }
        .piliInteractiveDismissDisabled(busy)
        .onAppear { value = currentValue; birthday = formatter.date(from: profile.birthday ?? "") ?? formatter.date(from: "2000-01-01")! }
        .piliAlert("消耗 6 硬币修改昵称？", isPresented: $confirmName) {
            PiliAlertButton("取消", role: .cancel) {}
            PiliAlertButton("确认修改") { save() }
        } message: { "新昵称：\(value)" }
    }
    private func save() {
        guard canSave else { return }
        let submitted = submittedValue
        busy = true; errorMessage = nil
        Task {
            defer { busy = false }
            do { try await api.updatePiliProfile(field, value: submitted, identity: identity); onSaved(); dismiss() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
