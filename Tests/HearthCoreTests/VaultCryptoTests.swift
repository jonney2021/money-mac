import XCTest
import CryptoKit
@testable import HearthCore
final class VaultCryptoTests: XCTestCase {
    func testPasswordVaultAndWrongCredentials() throws {
        let open = try VaultCrypto.create(username:"family",password:"test-password-12345")
        let data = try VaultCrypto.encode(open.envelope)
        XCTAssertEqual(try VaultCrypto.open(data,username:"family",password:"test-password-12345").ledger.entries.count,0)
        XCTAssertThrowsError(try VaultCrypto.open(data,username:"wrong",password:"test-password-12345"))
        XCTAssertThrowsError(try VaultCrypto.open(data,username:"family",password:"incorrect-password"))
        XCTAssertFalse(String(data:data,encoding:.utf8)!.contains("test-password"))
    }
    func testTamperedMetadataOrCiphertextIsRejected() throws {
        let open = try VaultCrypto.create(username:"family",password:"test-password-12345")
        var e = open.envelope; e.username="attacker"
        XCTAssertThrowsError(try VaultCrypto.open(VaultCrypto.encode(e),username:nil,password:"test-password-12345"))
        e=open.envelope;e.sealed[e.sealed.count-1] ^= 1
        XCTAssertThrowsError(try VaultCrypto.open(VaultCrypto.encode(e),username:nil,password:"test-password-12345"))
    }
    func testRejectsInvalidKDFParameters() throws {
        XCTAssertThrowsError(try VaultCrypto.derive("password",salt:Data(repeating:0,count:16),rounds:Int.max))
        XCTAssertThrowsError(try VaultCrypto.create(username:"u",password:"short"))
    }
    func testVaultEncryptedPayloadSurvivesBackup() throws {
        var open=try VaultCrypto.create(username:"family",password:"test-password-12345")
        open.ledger.entries=[LedgerEntry(cents:12345,merchant:"PRIVATE-MERCHANT")]
        open.envelope.sealed=try AES.GCM.seal(JSONEncoder().encode(open.ledger),using:open.key,authenticating:VaultCrypto.aad(open.envelope)).combined!
        let data=try VaultCrypto.encode(open.envelope)
        XCTAssertFalse(String(data:data,encoding:.utf8)!.contains("PRIVATE-MERCHANT"))
        XCTAssertEqual(try VaultCrypto.open(data,username:nil,password:"test-password-12345").ledger.entries.first?.cents,12345)
    }
}
