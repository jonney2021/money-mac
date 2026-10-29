import XCTest
import CryptoKit
@testable import HearthCore

final class HearthCoreTests: XCTestCase {
    let alert = "Your card ending 1234 was used at COSTCO for CAD 86.42 on 2026-10-24."
    func testMoneyUsesExactCents() throws {
        XCTAssertEqual(try Money.cents("0.29"), 29)
        XCTAssertEqual(try Money.cents("12.3"), 1230)
        for value in ["0", "-1", "1.001", "1,000", "nan", "100000000", ""] { XCTAssertThrowsError(try Money.cents(value)) }
    }
    func testDateValidation() { XCTAssertNil(Day.date("2026-02-30")); XCTAssertNotNil(Day.date("2028-02-29")) }
    func testParsing() throws {
        let entry = try AlertParser.parse(alert)
        XCTAssertEqual(entry.cents, 8642); XCTAssertEqual(entry.merchant, "COSTCO"); XCTAssertEqual(entry.category, .groceries); XCTAssertTrue(entry.needsReview)
        XCTAssertEqual(try AlertParser.parse(alert.replacingOccurrences(of: "CAD 86.42", with: "86.42 CAD")).cents, 8642)
    }
    func testRejectsUnsupportedAlerts() {
        for text in [alert + " Balance CAD 200.00", alert.replacingOccurrences(of: "CAD", with: "USD"), alert.replacingOccurrences(of: "CAD ", with: ""), alert + " refund", alert + " pending", alert.replacingOccurrences(of: "2026-10-24", with: "2026-02-30")] { XCTAssertThrowsError(try AlertParser.parse(text)) }
    }
    func testDuplicateAndTombstone() throws {
        var ledger = Ledger(); let e = try AlertParser.parse(alert)
        XCTAssertEqual(try ledger.merge([e,e]),1); XCTAssertEqual(try ledger.merge([e]),0)
        ledger.remove(e); XCTAssertEqual(try ledger.merge([e]),0); XCTAssertTrue(ledger.entries.isEmpty)
    }
    func testMergeIsAtomic() throws {
        var ledger = Ledger(); let e = try AlertParser.parse(alert); var bad = e; bad.id = "bad"; bad.cents = -5; bad.sourceID = "other"
        XCTAssertThrowsError(try ledger.merge([e,bad])); XCTAssertTrue(ledger.entries.isEmpty)
    }
    func testMonthAndIncomeExpense() throws {
        var ledger = Ledger(); ledger.entries = [LedgerEntry(kind: .income, cents: 10000, merchant: "工资", date: "2026-10-01"),LedgerEntry(cents: 290, merchant: "咖啡", date: "2026-10-02"),LedgerEntry(cents: 100, merchant: "旧记录", date: "2026-09-02")]
        XCTAssertEqual(ledger.total(.income,month:"2026-10"),10000); XCTAssertEqual(ledger.total(.expense,month:"2026-10"),290)
    }
    func testCSVEscapesFormulaAndQuotes() {
        var ledger=Ledger(); ledger.entries=[LedgerEntry(cents: 100,merchant:"=HYPERLINK(\"x\")")]
        XCTAssertTrue(ledger.csv.contains("'=HYPERLINK(\"\"x\"\")"))
    }
    func testRejectsDuplicateIDsAndSources() {
        var ledger=Ledger(); let e=LedgerEntry(cents:100,merchant:"A");ledger.entries=[e,e];XCTAssertThrowsError(try ledger.validate())
    }
    func testPythonEncryptedFeedVector() throws {
        let data = Data(#"{"format":"hearth-feed-v1","sealed":"8UP15ZZIwwhTH3BohilB13zBgL/c4ALif1Xmg5H+o5Sa4nvVXjGpN8gNC3Ry/1jOftg4Tt7xHwnZvMpciNd0VMIlxOrGqvS0zupBt1+wvrfq4ivhyNSbTJcSyjiW00XG/0K741xeWX4ufCHpLOZjJ4oF7gbbPAs4YL3nvsjN6lkLapTMARwq6mFxMG1iNl8croWvvrDYYrvNinOftaf2l4xjKLT6Fy9y42XtsMNQs5S7+gZ88GX24b/XOLUIwZBId5uUG9QPr8kLJyHrdC0IDfOJUD+9T4YRsDD8TgMu/3jpBAFyj1ATea+BEVm2A7L2wEmYRcPOF5PtkBTNdhGFECLHgfcRq4hQGQAJT1bwEhz8R/KjcAwn+060JMSp5NkDXFUefOeVy1jWS0PpRuMmM92PSpVDrgFTqS936UTIVbP27xR1XHyp5hHZ4UTaYSUgiF3n1Kft3MjhdKwCjPJI0sfi+nx1LKtFxkHQ0JL+MmgvExuPOVsT/HbT6WE="}"#.utf8)
        let entries = try FeedCrypto.open(data,hex:String(repeating:"01",count:32))
        XCTAssertEqual(entries.count,1);XCTAssertEqual(entries[0].cents,8642)
        XCTAssertThrowsError(try FeedCrypto.open(data,hex:String(repeating:"02",count:32)))
    }
    func testSwiftEncryptedFeedRoundtrip() throws {
        let payload=FeedPayload(version:1,entries:[try AlertParser.parse(alert)])
        let key=try FeedCrypto.key(String(repeating:"03",count:32))
        let sealed=try AES.GCM.seal(JSONEncoder().encode(payload),using:key,authenticating:Data("hearth-feed-v1".utf8)).combined!
        let envelope=EncryptedFeed(format:"hearth-feed-v1",sealed:sealed)
        XCTAssertEqual(try FeedCrypto.open(JSONEncoder().encode(envelope),hex:String(repeating:"03",count:32)).first?.cents,8642)
    }
}
