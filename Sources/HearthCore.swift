import Foundation
import CryptoKit

public enum LedgerError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}
public enum EntryKind: String, Codable, CaseIterable { case expense, income }
public enum Category: String, Codable, CaseIterable, Identifiable {
    case groceries = "超市日用", dining = "餐饮美食", home = "居家账单", transport = "交通出行"
    case shopping = "购物消费", health = "健康医疗", leisure = "休闲娱乐", education = "教育学习", salary = "工资收入", other = "其他"
    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .groceries: return "basket"
        case .dining: return "cup.and.saucer"
        case .home: return "house"
        case .transport: return "tram"
        case .shopping: return "bag"
        case .health: return "heart"
        case .leisure: return "sparkles"
        case .education: return "book"
        case .salary: return "arrow.down.left"
        case .other: return "square.grid.2x2"
        }
    }
    public static func suggested(for merchant: String) -> Category {
        let s = merchant.lowercased()
        if ["costco", "walmart", "metro", "iga", "provigo", "super c"].contains(where: s.contains) { return .groceries }
        if ["coffee", "tim hortons", "restaurant", "starbucks"].contains(where: s.contains) { return .dining }
        if ["hydro", "bell", "videotron"].contains(where: s.contains) { return .home }
        if ["stm", "uber", "esso", "shell"].contains(where: s.contains) { return .transport }
        return .other
    }
}
public enum Money {
    public static let maximum: Int64 = 9_999_999_999
    public static func cents(_ text: String) throws -> Int64 {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.range(of: #"^\d{1,8}(?:\.\d{1,2})?$"#, options: .regularExpression) != nil else {
            throw LedgerError.invalid("金额请使用数字和小数点，最多两位小数。")
        }
        let p = t.split(separator: ".", omittingEmptySubsequences: false)
        guard let whole = Int64(p[0]) else { throw LedgerError.invalid("金额无效") }
        let fraction = p.count == 2 ? Int64((String(p[1]) + "00").prefix(2))! : 0
        let v = whole * 100 + fraction
        guard v > 0 && v <= maximum else { throw LedgerError.invalid("金额必须大于 0，且小于一亿加元。") }
        return v
    }
    public static func text(_ cents: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency; formatter.currencyCode = "CAD"; formatter.locale = Locale(identifier: "en_CA")
        return formatter.string(from: NSDecimalNumber(value: cents).dividing(by: 100)) ?? "$0.00"
    }
    public static func editable(_ cents: Int64) -> String { String(format: "%.2f", Double(cents) / 100) }
}
public enum Day {
    public static func string(_ date: Date) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    public static func date(_ value: String) -> Date? {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        guard let result = f.date(from: value), string(result) == value else { return nil }; return result
    }
    public static func month(_ date: Date) -> String { String(string(date).prefix(7)) }
}
public struct LedgerEntry: Codable, Identifiable, Equatable {
    public var id: String
    public var kind: EntryKind
    public var cents: Int64
    public var merchant: String
    public var date: String
    public var category: Category
    public var member: String
    public var account: String
    public var note: String
    public var sourceID: String?
    public var needsReview: Bool
    public init(id: String = UUID().uuidString, kind: EntryKind = .expense, cents: Int64, merchant: String, date: String = Day.string(Date()), category: Category = .other, member: String = "共同", account: String = "信用卡", note: String = "", sourceID: String? = nil, needsReview: Bool = false) {
        self.id = id; self.kind = kind; self.cents = cents; self.merchant = merchant; self.date = date
        self.category = category; self.member = member; self.account = account; self.note = note
        self.sourceID = sourceID; self.needsReview = needsReview
    }
    public func validate() throws {
        guard cents > 0, cents <= Money.maximum, Day.date(date) != nil, !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              merchant.count <= 200, note.count <= 2000, !id.isEmpty, id.count <= 128, member.count <= 50, account.count <= 50,
              (sourceID?.count ?? 0) <= 200 else { throw LedgerError.invalid("记录包含无效金额、日期或过长文本。") }
    }
}
public struct Ledger: Codable {
    public var version = 1
    public var entries: [LedgerEntry] = []
    public var budgets: [String: Int64] = [:]
    // Tombstones prevent a rejected/deleted email from reappearing on the next sync.
    public var ignoredSourceIDs: Set<String> = []
    public var syncKeyHex: String? = nil
    public var feedBookmark: Data? = nil
    public var lastSync: String? = nil
    public init() {}
    public func validate() throws {
        guard version == 1, entries.count <= 50_000, budgets.count <= 2400, ignoredSourceIDs.count <= 100_000,
              Set(entries.map(\.id)).count == entries.count else { throw LedgerError.invalid("账本格式或记录数量无效。") }
        let sources = entries.compactMap(\.sourceID)
        guard Set(sources).count == sources.count, budgets.allSatisfy({ $0.key.range(of: #"^\d{4}-(0[1-9]|1[0-2])$"#, options: .regularExpression) != nil && $0.value > 0 && $0.value <= Money.maximum }) else {
            throw LedgerError.invalid("账本包含重复邮件或无效预算。")
        }
        for e in entries { try e.validate() }
    }
    public func entries(in month: String) -> [LedgerEntry] { entries.filter { $0.date.hasPrefix(month) }.sorted { $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date } }
    public func total(_ kind: EntryKind, month: String) -> Int64 { entries(in: month).filter { $0.kind == kind }.reduce(0) { $0 + $1.cents } }
    public mutating func merge(_ new: [LedgerEntry]) throws -> Int {
        guard new.count <= 10_000 else { throw LedgerError.invalid("同步文件过大，请分批导入。") }
        var candidate = self; var sources = Set(entries.compactMap(\.sourceID)).union(ignoredSourceIDs); var ids = Set(entries.map(\.id)); var added = 0
        for e in new {
            try e.validate()
            guard let source = e.sourceID, !source.isEmpty else { throw LedgerError.invalid("邮件记录缺少去重标识。") }
            if sources.contains(source) || ids.contains(e.id) { continue }
            var item = e; item.needsReview = true; candidate.entries.append(item); added += 1; sources.insert(source); ids.insert(e.id)
        }
        try candidate.validate(); self = candidate; return added
    }
    public mutating func remove(_ e: LedgerEntry) {
        if let s = e.sourceID { ignoredSourceIDs.insert(s) }
        entries.removeAll { $0.id == e.id }
    }
    public var csv: String {
        func cell(_ s: String) -> String {
            let safe = ["=", "+", "-", "@", "\t", "\r"].contains(where: s.hasPrefix) ? "'" + s : s
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let header = ["日期", "收支", "金额 CAD", "分类", "商户", "成员", "账户", "备注", "待核对"]
        let rows = entries.sorted { $0.date > $1.date }.map { [$0.date, $0.kind == .expense ? "支出" : "收入", Money.editable($0.cents), $0.category.rawValue, $0.merchant, $0.member, $0.account, $0.note, $0.needsReview ? "是" : "否"] }
        return "\u{feff}" + ([header] + rows).map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n")
    }
}
public enum AlertParser {
    private static func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { m in
            (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: text).map { String(text[$0]) } ?? "" }
        }
    }
    public static func parse(_ raw: String, messageID: String? = nil) throws -> LedgerEntry {
        guard raw.count <= 100_000 else { throw LedgerError.invalid("邮件内容过长。") }
        let text = raw.replacingOccurrences(of: "\u{00a0}", with: " ").replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard matches(#"\b(?:USD|EUR|GBP|CNY|HKD)\b|US\$|美元|人民币|欧元"#, text).isEmpty else {
            throw LedgerError.invalid("仅支持加元 CAD，外币请手工记录。")
        }
        guard matches(#"\b(?:refund|refunded|payment received|payment due|statement|declined|reversed|pending)\b|退款|还款|账单|拒绝|撤销|待处理"#, text).isEmpty else {
            throw LedgerError.invalid("通知可能是账单、退款、还款或非最终交易，请手工核对。")
        }
        guard !matches(#"\b(?:purchase|purchased|transaction|was used|spent)\b|消费|交易"#, text).isEmpty else { throw LedgerError.invalid("未识别为消费交易通知。") }
        let amounts = matches(#"(?:CAD\s*\$?|C\$|\$)\s*((?:\d{1,3}(?:,\d{3})+|\d+)\.\d{2})(?!\d)|((?:\d{1,3}(?:,\d{3})+|\d+)\.\d{2})\s*CAD\b"#, text)
        guard amounts.count == 1 else { throw LedgerError.invalid("邮件必须只含一个明确金额，多个金额请手工记录。") }
        guard !matches(#"\bCAD\b|C\$"#, text).isEmpty else { throw LedgerError.invalid("只有 $ 无法确认币种，请手工选择 CAD。") }
        let cents = try Money.cents((amounts[0][1].isEmpty ? amounts[0][2] : amounts[0][1]).replacingOccurrences(of: ",", with: ""))
        let merchant = matches(#"\bat\s+([^\r\n]+?)\s+(?:for|on)\b|(?:商户|商家)[：:]\s*([^\r\n，,。]+)"#, text).first
        guard let m = merchant else { throw LedgerError.invalid("无法识别商户，请手工记录。") }
        let name = (m[1].isEmpty ? m[2] : m[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        let dates = Set(matches(#"\b20\d{2}-\d{2}-\d{2}\b"#, text).map { $0[0] })
        guard dates.count == 1, let date = dates.first, Day.date(date) != nil else { throw LedgerError.invalid("需要一个明确的 YYYY-MM-DD 交易日期。") }
        let normalized = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
        let hash = SHA256.hash(data: Data((messageID ?? normalized).utf8)).map { String(format: "%02x", $0) }.joined()
        let e = LedgerEntry(cents: cents, merchant: name, date: date, category: .suggested(for: name), sourceID: "mail:" + hash, needsReview: true)
        try e.validate(); return e
    }
}
public struct EncryptedFeed: Codable {
    public var format: String
    public var sealed: Data // base64 nonce (12) + ciphertext + GCM tag (16)
}
public struct FeedPayload: Codable {
    public var version: Int
    public var entries: [LedgerEntry]
}
public enum FeedCrypto {
    public static func key(_ hex: String) throws -> SymmetricKey {
        let h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard h.count == 64, h.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else { throw LedgerError.invalid("同步密钥应为 64 位十六进制字符。") }
        var data = Data(); var i = h.startIndex
        while i < h.endIndex { let j = h.index(i, offsetBy: 2); data.append(UInt8(h[i..<j], radix: 16)!); i = j }
        return SymmetricKey(data: data)
    }
    public static func open(_ data: Data, hex: String) throws -> [LedgerEntry] {
        guard data.count <= 12_000_000 else { throw LedgerError.invalid("同步文件超过 12 MB。") }
        let envelope = try JSONDecoder().decode(EncryptedFeed.self, from: data)
        guard envelope.format == "hearth-feed-v1" else { throw LedgerError.invalid("同步文件格式不匹配。") }
        let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.sealed), using: key(hex), authenticating: Data("hearth-feed-v1".utf8))
        let payload = try JSONDecoder().decode(FeedPayload.self, from: plain)
        guard payload.version == 1 else { throw LedgerError.invalid("不支持的同步版本。") }
        return payload.entries
    }
}
