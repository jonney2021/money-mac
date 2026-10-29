import Foundation
import CryptoKit
import CommonCrypto
import Security

struct VaultEnvelope: Codable {
    var version = 1
    var vaultID: String
    var username: String
    var salt: Data
    var rounds: Int
    var wrappedKey: Data
    var sealed: Data
}
struct OpenVault {
    var envelope: VaultEnvelope
    var key: SymmetricKey
    var ledger: Ledger
}
enum VaultCrypto {
    static let rounds = 600_000
    static func random(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { throw LedgerError.invalid("系统无法生成安全随机数。") }
        return Data(bytes)
    }
    static func derive(_ password: String, salt: Data, rounds: Int) throws -> SymmetricKey {
        guard password.utf8.count <= 1024, salt.count == 16, (100_000...1_000_000).contains(rounds) else { throw LedgerError.invalid("密码或备份参数无效。") }
        var output = [UInt8](repeating: 0, count: 32)
        let status = password.withCString { ptr in salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), ptr, password.utf8.count, saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(rounds), &output, 32)
        } }
        guard status == kCCSuccess else { throw LedgerError.invalid("密钥派生失败。") }
        return SymmetricKey(data: output)
    }
    static func aad(_ e: VaultEnvelope) -> Data { Data("hearth-vault-v1|\(e.vaultID)|\(e.username)".utf8) }
    static func encode(_ e: VaultEnvelope) throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(e) }
    static func read(_ data: Data) throws -> VaultEnvelope {
        guard data.count <= 32_000_000 else { throw LedgerError.invalid("备份超过 32 MB。") }
        let e = try JSONDecoder().decode(VaultEnvelope.self, from: data)
        guard e.version == 1, !e.vaultID.isEmpty, e.vaultID.count <= 64, !e.username.isEmpty, e.username.count <= 40,
              e.salt.count == 16, (100_000...1_000_000).contains(e.rounds), e.wrappedKey.count == 60 else { throw LedgerError.invalid("账本文件格式不受支持。") }
        return e
    }
    static func unpack(_ e: VaultEnvelope, key: SymmetricKey) throws -> OpenVault {
        let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: e.sealed), using: key, authenticating: aad(e))
        let ledger = try JSONDecoder().decode(Ledger.self, from: plain); try ledger.validate()
        return OpenVault(envelope: e, key: key, ledger: ledger)
    }
    static func open(_ data: Data, username: String?, password: String) throws -> OpenVault {
        let e = try read(data)
        guard username == nil || username == e.username else { throw LedgerError.invalid("用户名或密码不正确。") }
        do {
            let wrapping = try derive(password, salt: e.salt, rounds: e.rounds)
            let key = try AES.GCM.open(AES.GCM.SealedBox(combined: e.wrappedKey), using: wrapping, authenticating: aad(e))
            return try unpack(e, key: SymmetricKey(data: key))
        } catch { throw LedgerError.invalid("密码不正确，或文件已损坏。") }
    }
    static func create(username: String, password: String) throws -> OpenVault {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...40).contains(username.count), password.count >= 10, password.utf8.count <= 1024 else { throw LedgerError.invalid("用户名需 2–40 个字符，密码至少 10 个字符。") }
        let key = SymmetricKey(data: try random(32)); let salt = try random(16)
        var envelope = VaultEnvelope(vaultID: UUID().uuidString, username: username, salt: salt, rounds: rounds, wrappedKey: Data(), sealed: Data())
        envelope.wrappedKey = try AES.GCM.seal(key.withUnsafeBytes { Data($0) }, using: derive(password, salt: salt, rounds: rounds), authenticating: aad(envelope)).combined!
        envelope.sealed = try AES.GCM.seal(JSONEncoder().encode(Ledger()), using: key, authenticating: aad(envelope)).combined!
        return OpenVault(envelope: envelope, key: key, ledger: Ledger())
    }
}
