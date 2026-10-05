import Foundation
import PiliPlaybackCore
import Security

@MainActor
enum PiliSettingsBackup {
    static func capture() throws -> SettingsArchive {
        try SettingsArchive.capture(UserDefaults.standard.dictionaryRepresentation())
    }
    static func export() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PiliPlusSwift-settings-\(UUID().uuidString).json")
        try JSONEncoder().encode(capture()).write(to: url, options: .atomic)
        return url
    }
    static func apply(_ archive: SettingsArchive, libraryStore: LibraryStore) throws {
        let values = try archive.decodedValues()
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let previous = root.appendingPathComponent("PiliPlusSwift-settings-before-restore.json")
        try JSONEncoder().encode(capture()).write(to: previous, options: .atomic)
        guard let domain = Bundle.main.bundleIdentifier else { throw SettingsArchive.ArchiveError.invalidFormat }
        var current = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        for key in Array(current.keys) where SettingsArchive.allows(key) { current.removeValue(forKey: key) }
        current.merge(values) { _, new in new }
        UserDefaults.standard.setPersistentDomain(current, forName: domain)
        libraryStore.reloadPiliSettings()
    }
    static func rollback(libraryStore: LibraryStore) throws {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let archive = try SettingsArchive.decode(Data(contentsOf: root.appendingPathComponent("PiliPlusSwift-settings-before-restore.json")))
        try apply(archive, libraryStore: libraryStore)
    }
}

/// Settings backups must never contain the WebDAV password, including on an unsigned simulator.
@MainActor
enum PiliWebDAVCredentialStore {
    private static let service = "io.github.syiar.PiliPlusSwift.WebDAV"
    static func read() throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: "connection",
                                   kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError.unhandled(status) }
        return String(decoding: data, as: UTF8.self)
    }
    static func save(_ password: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: "connection"]
        let attributes: [String: Any] = [kSecValueData as String: Data(password.utf8),
                                        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError.unhandled(status) }
        let add = query.merging(attributes) { _, new in new }
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError.unhandled(added) }
    }
}
