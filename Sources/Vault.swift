import Foundation
import CryptoKit
import CommonCrypto
import Security
import LocalAuthentication
import SwiftUI
import UIKit

@MainActor final class VaultStore: ObservableObject {
    @Published private(set) var ledger = Ledger()
    @Published private(set) var isUnlocked = false
    @Published private(set) var hasAccount = false
    @Published private(set) var username = ""
    @Published var message: String?
    @Published private(set) var busy = false
    @Published private(set) var biometricsEnabled = false
    private var current: OpenVault?
    private var failedAttempts = 0
    private var retryAfter = Date.distantPast
    private let file: URL
    private let service = "app.hearth.local.biometric-vault"
    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Hearth", isDirectory: true)
        file = folder.appendingPathComponent("ledger.hearth")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                hasAccount = true
                let e = try VaultCrypto.read(Data(contentsOf: file)); username = e.username
                biometricsEnabled = UserDefaults.standard.bool(forKey: "biometry." + e.vaultID)
            }
        } catch { hasAccount = FileManager.default.fileExists(atPath: file.path); message = "账本无法读取，请从加密备份恢复。不会覆盖原文件。" }
    }
    private func write(_ open: OpenVault) throws {
        let data = try VaultCrypto.encode(open.envelope)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
    }
    private func accept(_ open: OpenVault) {
        username = open.envelope.username; hasAccount = true
        biometricsEnabled = UserDefaults.standard.bool(forKey: "biometry." + open.envelope.vaultID)
        guard UIApplication.shared.applicationState != .background else { return }
        current = open; ledger = open.ledger; isUnlocked = true
        failedAttempts = 0; retryAfter = .distantPast
    }
    func register(username: String, password: String) async {
        guard !busy, !hasAccount else { return }; busy = true; defer { busy = false }
        do { let open = try await Task.detached(priority: .userInitiated) { try VaultCrypto.create(username: username, password: password) }.value
            try write(open); accept(open)
        } catch { message = error.localizedDescription }
    }
    func login(username: String, password: String) async {
        guard !busy else { return }
        guard Date() >= retryAfter else { message = "尝试次数较多，请稍后再试。"; return }
        busy = true; defer { busy = false }
        do {
            let data = try Data(contentsOf: file)
            let open = try await Task.detached(priority: .userInitiated) { try VaultCrypto.open(data, username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password) }.value
            accept(open)
        } catch {
            failedAttempts += 1
            if failedAttempts >= 5 { retryAfter = Date().addingTimeInterval(30) }
            message = error.localizedDescription
        }
    }
    func lock() { current = nil; ledger = Ledger(); isUnlocked = false }
    // Mutate a copy, validate and commit it to disk before publishing to the UI.
    func update(_ mutation: (inout Ledger) throws -> Void) throws {
        guard var open = current, isUnlocked else { throw LedgerError.invalid("请先解锁账本。") }
        var candidate = ledger; try mutation(&candidate); try candidate.validate()
        open.ledger = candidate
        open.envelope.sealed = try AES.GCM.seal(JSONEncoder().encode(candidate), using: open.key, authenticating: VaultCrypto.aad(open.envelope)).combined!
        try write(open); current = open; ledger = candidate
    }
    func save(_ entry: LedgerEntry) {
        do { try entry.validate(); try update { l in
            if let i = l.entries.firstIndex(where: { $0.id == entry.id }) { l.entries[i] = entry } else { l.entries.append(entry) }
        } } catch { message = error.localizedDescription }
    }
    func delete(_ entry: LedgerEntry) { do { try update { $0.remove(entry) } } catch { message = error.localizedDescription } }
    func merge(_ entries: [LedgerEntry]) {
        do { var count = 0; try update { count = try $0.merge(entries); $0.lastSync = ISO8601DateFormatter().string(from: Date()) }; message = "已导入 \(count) 笔；重复邮件已跳过。邮件账目均标记为待核对。" }
        catch { message = error.localizedDescription }
    }
    func setBudget(_ cents: Int64, month: String) { do { try update { $0.budgets[month] = cents } } catch { message = error.localizedDescription } }
    func backup() throws -> Data { guard let current else { throw LedgerError.invalid("请先解锁。") }; return try VaultCrypto.encode(current.envelope) }
    func restore(_ data: Data, password: String) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let open = try await Task.detached(priority: .userInitiated) { try VaultCrypto.open(data, username: nil, password: password) }.value
            // A restore must never silently enable old biometric credentials.
            if let e = current?.envelope { disableBiometrics(id: e.vaultID) }
            if FileManager.default.fileExists(atPath: file.path) { try Data(contentsOf: file).write(to: file.appendingPathExtension("previous"), options: [.atomic, .completeFileProtection]) }
            UserDefaults.standard.set(false, forKey: "biometry." + open.envelope.vaultID)
            try write(open); accept(open); message = "已恢复账本。请重新配置 Face ID 和邮件同步文件。"
            try update { $0.feedBookmark = nil }
        } catch { message = error.localizedDescription }
    }
    func changePassword(old: String, new: String) async {
        guard !busy, let open = current else { return }; busy = true; defer { busy = false }
        do {
            guard new.count >= 10, new.utf8.count <= 1024 else { throw LedgerError.invalid("新密码至少 10 个字符。") }
            let backup = try VaultCrypto.encode(open.envelope)
            var revised = try await Task.detached(priority: .userInitiated) { try VaultCrypto.open(backup, username: nil, password: old) }.value
            let salt = try VaultCrypto.random(16)
            revised.envelope.salt = salt; revised.envelope.rounds = VaultCrypto.rounds
            let wrapping = try await Task.detached(priority: .userInitiated) { try VaultCrypto.derive(new, salt: salt, rounds: VaultCrypto.rounds) }.value
            guard isUnlocked, current?.envelope.vaultID == open.envelope.vaultID else { throw LedgerError.invalid("账本已锁定，请重新登录后再改密码。") }
            revised.envelope.wrappedKey = try AES.GCM.seal(revised.key.withUnsafeBytes { Data($0) }, using: wrapping, authenticating: VaultCrypto.aad(revised.envelope)).combined!
            try write(revised); current = revised; message = "密码已更新。旧备份仍使用导出时的旧密码。"
        } catch { message = error.localizedDescription }
    }
    private func keychainQuery(id: String) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id] }
    private func disableBiometrics(id: String) { SecItemDelete(keychainQuery(id: id) as CFDictionary); UserDefaults.standard.set(false, forKey: "biometry." + id); biometricsEnabled = false }
    func disableBiometrics() { if let e = current?.envelope { disableBiometrics(id: e.vaultID) } }
    func enableBiometrics() async {
        guard let open = current else { return }
        let context = LAContext(); var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { message = "请先在 iPhone 设置中启用 Face ID / Touch ID 和设备密码。"; return }
        do {
            guard try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "为小家账本启用生物识别解锁") else { return }
            guard isUnlocked else { return }
            var accessError: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, &accessError) else { throw LedgerError.invalid("无法创建受生物识别保护的密钥。") }
            disableBiometrics(id: open.envelope.vaultID)
            var q = keychainQuery(id: open.envelope.vaultID); q[kSecValueData as String] = open.key.withUnsafeBytes { Data($0) }; q[kSecAttrAccessControl as String] = access
            let status = SecItemAdd(q as CFDictionary, nil)
            guard status == errSecSuccess else { throw LedgerError.invalid("Face ID 密钥保存失败，请使用密码登录。") }
            UserDefaults.standard.set(true, forKey: "biometry." + open.envelope.vaultID); biometricsEnabled = true
        } catch { message = "未启用生物识别：\(error.localizedDescription)" }
    }
    func unlockBiometrics() async {
        guard !busy, biometricsEnabled else { return }; busy = true; defer { busy = false }
        do {
            let envelope = try VaultCrypto.read(Data(contentsOf: file))
            let context = LAContext(); context.localizedReason = "解锁小家家庭账本"; context.localizedFallbackTitle = "使用账本密码"
            var q = keychainQuery(id: envelope.vaultID); q[kSecReturnData as String] = true; q[kSecUseAuthenticationContext as String] = context
            var item: CFTypeRef?
            let status = SecItemCopyMatching(q as CFDictionary, &item)
            guard status == errSecSuccess, let keyData = item as? Data else { throw LedgerError.invalid("生物识别未完成或已失效，请使用账本密码登录。") }
            accept(try VaultCrypto.unpack(envelope, key: SymmetricKey(data: keyData)))
        } catch { message = error.localizedDescription }
    }
    func createSyncKey() {
        do { let hex = try VaultCrypto.random(32).map { String(format: "%02x", $0) }.joined(); try update { $0.syncKeyHex = hex } }
        catch { message = error.localizedDescription }
    }
    func setSyncKey(_ hex: String) {
        do { _ = try FeedCrypto.key(hex); try update { $0.syncKeyHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() } }
        catch { message = error.localizedDescription }
    }
    func selectFeed(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            try update { $0.feedBookmark = bookmark }; try readFeed(url)
        } catch { message = "同步文件读取失败：\(error.localizedDescription)" }
    }
    private func readFeed(_ url: URL) throws {
        guard let hex = ledger.syncKeyHex else { throw LedgerError.invalid("请先配置同步密钥。") }
        var readError: Error?; var coordinateError: NSError?; var entries: [LedgerEntry] = []
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinateError) { location in
            do {
                let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 12_000_000 else { throw LedgerError.invalid("同步文件过大。") }
                entries = try FeedCrypto.open(Data(contentsOf: location), hex: hex)
            } catch { readError = error }
        }
        if let error = coordinateError { throw error }; if let error = readError { throw error }
        var count = 0
        try update { count = try $0.merge(entries); $0.lastSync = ISO8601DateFormatter().string(from: Date()) }
        if count > 0 { message = "邮件同步：新增 \(count) 笔待核对账目。" }
    }
    func refreshFeed() {
        guard isUnlocked, let bookmark = ledger.feedBookmark else { return }
        do {
            var stale = false; let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            if stale { let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil); try update { $0.feedBookmark = data } }
            try readFeed(url)
        } catch { message = "邮件同步尚未完成：请确认同步文件已下载，或重新选择文件。原有记录保持不变。" }
    }
    func disconnectFeed() { do { try update { $0.feedBookmark = nil; $0.lastSync = nil } } catch { message = error.localizedDescription } }
}
