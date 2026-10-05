import Foundation

nonisolated struct PiliAccountIdentity: Hashable, Sendable {
    let mid: Int
    let version: Int
    init(_ snapshot: BiliAPIClient.RequestSnapshot) {
        mid = snapshot.currentUserMID ?? 0; version = snapshot.playbackCredentialVersion
    }
    func matches(_ snapshot: BiliAPIClient.RequestSnapshot) -> Bool {
        snapshot.isLoggedIn && snapshot.currentUserMID == mid && snapshot.playbackCredentialVersion == version
    }
}

nonisolated enum PiliProfileField: String, CaseIterable, Identifiable, Sendable {
    case uname, sign, sex, birthday
    var id: String { rawValue }
    var title: String {
        switch self { case .uname: "昵称"; case .sign: "个性签名"; case .sex: "性别"; case .birthday: "生日" }
    }
}

nonisolated struct PiliOwnProfile: Sendable {
    let mid: Int
    let name: String
    let face: String?
    let sign: String
    let sex: Int?
    let birthday: String?
    let coins: Double?
    init(_ value: DynamicJSONValue) throws {
        guard let object = value.objectValueForDynamicParsing, let mid = object["mid"]?.intValueForDynamicParsing, mid > 0 else {
            throw BiliAPIError.missingPayload
        }
        self.mid = mid
        name = object["name"]?.textValueForDynamicParsing ?? object["uname"]?.textValueForDynamicParsing ?? ""
        face = object["face"]?.textValueForDynamicParsing?.normalizedBiliURL()
        sign = object["sign"]?.textValueForDynamicParsing ?? ""
        let rawSex = object["sex"]?.textValueForDynamicParsing
        sex = object["sex"]?.intValueForDynamicParsing ?? ["男": 1, "女": 2, "保密": 0][rawSex ?? ""]
        birthday = object["birthday"]?.textValueForDynamicParsing
        coins = (object["coins"]?.textValueForDynamicParsing ?? object["money"]?.textValueForDynamicParsing).flatMap(Double.init)
    }
}

extension BiliAPIClient {
    func fetchPiliOwnProfile(identity: PiliAccountIdentity) async throws -> PiliOwnProfile {
        let context = await requestSnapshot(purpose: .main)
        guard identity.matches(context) else { throw PiliOfflineError.message("账号已切换，请重新打开个人资料") }
        let response: BiliResponse<DynamicJSONValue>
        if let key = context.appAccessKey, !key.isEmpty {
            response = try await get(base: appURL, path: "/x/v2/account/myinfo", query: BiliAppSigner.sign(Self.piliProfileParameters(key), profile: .androidHD),
                                     userAgent: BiliAppSigner.Profile.androidHD.userAgent, cookieHeader: context.cookieHeader,
                                     cachePolicy: .reloadIgnoringLocalCacheData)
        } else {
            response = try await get(base: baseURL, path: "/x/member/web/account", query: [:], cookieHeader: context.cookieHeader,
                                     cachePolicy: .reloadIgnoringLocalCacheData)
        }
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let data = response.payload else { throw BiliAPIError.missingPayload }
        let result = try PiliOwnProfile(data)
        guard result.mid == identity.mid else { throw PiliOfflineError.message("个人资料账号不一致，请重新登录") }
        return result
    }
    func updatePiliProfile(_ field: PiliProfileField, value: String, identity: PiliAccountIdentity) async throws {
        let context = await requestSnapshot(purpose: .main)
        guard identity.matches(context) else { throw PiliOfflineError.message("账号已切换，请重新打开个人资料") }
        guard let accessKey = context.appAccessKey, !accessKey.isEmpty else {
            throw PiliOfflineError.message("修改此项需要 App 登录，请在登录页使用 App 扫码或短信登录")
        }
        switch field {
        case .uname:
            guard (1...16).contains(value.count), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PiliOfflineError.message("昵称需为 1–16 个字")
            }
        case .sign:
            guard value.count <= 70 else { throw PiliOfflineError.message("个性签名最多 70 个字") }
        case .sex:
            guard ["0", "1", "2"].contains(value) else { throw BiliAPIError.missingPayload }
        case .birthday:
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"
            formatter.isLenient = false
            guard let date = formatter.date(from: value), date <= Date(), formatter.string(from: date) == value else {
                throw PiliOfflineError.message("请选择有效的出生日期")
            }
        }
        var fields = Self.piliProfileParameters(accessKey)
        fields[field == .sign ? "user_sign" : field.rawValue] = value
        let response: BiliResponse<DynamicJSONValue> = try await postForm(base: baseURL, path: "/x/member/app/\(field.rawValue)/update",
            body: BiliAppSigner.sign(fields, profile: .androidHD), userAgent: BiliAppSigner.Profile.androidHD.userAgent,
            cookieHeader: context.cookieHeader,
            retryPolicy: .init(label: "profileUpdate", attempts: 1, baseDelayNanoseconds: 0, maxDelayNanoseconds: 0, jitterNanoseconds: 0))
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
    }
    func updatePiliAvatar(jpeg: Data, identity: PiliAccountIdentity) async throws {
        let context = await requestSnapshot(purpose: .main)
        guard identity.matches(context) else { throw PiliOfflineError.message("账号已切换，请重新打开个人资料") }
        guard let csrf = context.csrfToken, !csrf.isEmpty else { throw BiliAPIError.missingCSRF }
        guard !jpeg.isEmpty, jpeg.count <= 5 * 1024 * 1024 else { throw PiliOfflineError.message("头像图片需小于 5 MB") }
        let response: BiliResponse<DynamicJSONValue> = try await postMultipart(base: baseURL, path: "/x/member/web/face/update",
            query: ["csrf": csrf], fields: ["dopost": "save", "DisplayRank": "10000"], fileField: "face", fileName: "avatar.jpg", mimeType: "image/jpeg",
            fileData: jpeg, cookieHeader: context.cookieHeader,
            retryPolicy: .init(label: "avatarUpdate", attempts: 1, baseDelayNanoseconds: 0, maxDelayNanoseconds: 0, jitterNanoseconds: 0))
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
    }
    private nonisolated static func piliProfileParameters(_ accessKey: String) -> [String: String] {
        let profile = BiliAppSigner.Profile.androidHD
        return ["access_key": accessKey, "build": profile.build, "mobi_app": profile.mobiApp, "platform": profile.platform,
                "channel": profile.channel, "c_locale": "zh_CN", "s_locale": "zh_CN", "statistics": profile.statistics]
    }
}
