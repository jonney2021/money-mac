import SwiftUI
import Charts
import UniformTypeIdentifiers

struct HearthTheme {
    static let green = Color(red: 0.13, green: 0.30, blue: 0.25)
    static let paper = Color(red: 0.97, green: 0.97, blue: 0.94)
    static let muted = Color(red: 0.48, green: 0.53, blue: 0.48)
    static let palette: [Color] = [green, Color(red: 0.65, green: 0.73, blue: 0.55), Color(red: 0.81, green: 0.68, blue: 0.51), .gray, .brown, .mint, .orange, .teal, .cyan, .indigo]
}
struct HearthCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { VStack(alignment: .leading, spacing: 16) { content }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(.black.opacity(0.035))) }
}
struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17).foregroundStyle(.white).background(HearthTheme.green.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 15)) }
}
struct HearthPrivacyScreen: View {
    var body: some View { ZStack { HearthTheme.paper.ignoresSafeArea(); VStack(spacing: 16) { Image(systemName: "circle.lefthalf.filled").font(.system(size: 48)); Text("小家").font(.largeTitle.weight(.semibold)); Text("把生活，记在心上。").font(.caption).foregroundStyle(HearthTheme.muted) }.foregroundStyle(HearthTheme.green) }.accessibilityLabel("账本已遮挡") }
}
struct LoginView: View {
    @EnvironmentObject var store: VaultStore
    @State private var username = ""
    @State private var password = ""
    @State private var confirm = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack { Image(systemName: "circle.lefthalf.filled"); Text("小家").fontWeight(.semibold) }.font(.title).padding(.top, 45)
                VStack(alignment: .leading, spacing: 12) {
                    Text(store.hasAccount ? "欢迎回家。" : "给生活，一个小家。").font(.system(size: 34, weight: .semibold, design: .rounded))
                    Text(store.hasAccount ? "解锁账本，继续记录生活的点滴。" : "创建本机账号，让每一笔生活都清晰可见。").foregroundStyle(HearthTheme.muted)
                }
                HearthCard {
                    Text(store.hasAccount ? "登录本机账本" : "创建本机账号").font(.headline)
                    TextField("用户名", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().padding().background(HearthTheme.paper, in: RoundedRectangle(cornerRadius: 12))
                    SecureField("密码（至少 10 个字符）", text: $password).textContentType(store.hasAccount ? .password : .newPassword).padding().background(HearthTheme.paper, in: RoundedRectangle(cornerRadius: 12))
                    if !store.hasAccount { SecureField("再次输入密码", text: $confirm).textContentType(.newPassword).padding().background(HearthTheme.paper, in: RoundedRectangle(cornerRadius: 12)) }
                    Button {
                        guard store.hasAccount || password == confirm else { store.message = "两次密码不一致。"; return }
                        Task {
                            if store.hasAccount { await store.login(username: username, password: password) } else { await store.register(username: username, password: password) }
                            password = ""; confirm = ""
                        }
                    } label: { HStack { if store.busy { ProgressView().tint(.white) }; Text(store.hasAccount ? "登录" : "创建加密账本") } }.buttonStyle(PrimaryButton()).disabled(store.busy || username.isEmpty || password.isEmpty)
                    if store.hasAccount && store.biometricsEnabled {
                        Button { Task { await store.unlockBiometrics() } } label: { Label("Face ID / Touch ID 解锁", systemImage: "faceid").frame(maxWidth: .infinity).padding(.vertical, 10) }.disabled(store.busy)
                    }
                }
                Text("本机账号不是云端账号。密码用于加密账本，无法通过邮件找回；请妥善保存密码，并定期导出加密备份。Face ID 变更或失效后仍可使用账本密码登录。").font(.footnote).foregroundStyle(HearthTheme.muted).lineSpacing(5)
                RestoreButton()
                Text("FAMILY LEDGER  /  MAKE ROOM FOR WHAT MATTERS").font(.system(size: 9)).tracking(1.5).foregroundStyle(HearthTheme.muted).padding(.bottom, 30)
            }.padding(25).foregroundStyle(HearthTheme.green)
        }.background(HearthTheme.paper.ignoresSafeArea()).onAppear { username = store.username }
    }
}
struct LedgerShell: View {
    @State private var tab = 0
    @State private var add = false
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { OverviewView(add: $add) }.tabItem { Label("总览", systemImage: "square.grid.2x2") }.tag(0)
            NavigationStack { RecordsView() }.tabItem { Label("明细", systemImage: "list.bullet.rectangle") }.tag(1)
            NavigationStack { StatsView() }.tabItem { Label("统计", systemImage: "chart.donut") }.tag(2)
            NavigationStack { MailView() }.tabItem { Label("邮件", systemImage: "envelope") }.tag(3)
            NavigationStack { SettingsView() }.tabItem { Label("设置", systemImage: "gearshape") }.tag(4)
        }.sheet(isPresented: $add) { EntryEditor() }
    }
}
struct MonthPicker: View {
    @Binding var date: Date
    var body: some View {
        HStack {
            Button { move(-1) } label: { Image(systemName: "chevron.left").padding(10) }.accessibilityLabel("上个月")
            Spacer(); Text(date, format: .dateTime.year().month(.wide)).font(.subheadline.weight(.medium)); Spacer()
            Button { move(1) } label: { Image(systemName: "chevron.right").padding(10) }.accessibilityLabel("下个月")
        }.foregroundStyle(HearthTheme.green)
    }
    private func move(_ value: Int) { if let next = Calendar.current.date(byAdding: .month, value: value, to: date) { date = next } }
}
struct EntryRow: View {
    var entry: LedgerEntry
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: entry.category.symbol).font(.system(size: 19)).frame(width: 43, height: 43).background(HearthTheme.paper, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.merchant).font(.subheadline.weight(.medium)).lineLimit(1)
                Text("\(String(entry.date.suffix(5))) · \(entry.category.rawValue) · \(entry.member)").font(.caption2).foregroundStyle(HearthTheme.muted)
            }
            Spacer(minLength: 3)
            VStack(alignment: .trailing, spacing: 5) {
                Text((entry.kind == .expense ? "−" : "+") + Money.text(entry.cents)).font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(entry.kind == .income ? .green : HearthTheme.green)
                if entry.needsReview { Text("待核对").font(.caption2).foregroundStyle(.orange) } else { Text(entry.account).font(.caption2).foregroundStyle(HearthTheme.muted) }
            }
        }.padding(.vertical, 8).foregroundStyle(HearthTheme.green)
    }
}
struct EmptyLedger: View {
    var body: some View { VStack(spacing: 12) { Image(systemName: "leaf").font(.system(size: 35, weight: .ultraLight)); Text("从第一笔，慢慢记起。").font(.subheadline); Text("点击「记一笔」，开始记录你的小家。 ").font(.caption).foregroundStyle(HearthTheme.muted) }.frame(maxWidth: .infinity).padding(.vertical, 35).foregroundStyle(HearthTheme.green) }
}
struct OverviewView: View {
    @EnvironmentObject var store: VaultStore
    @Binding var add: Bool
    @State private var date = Date()
    @State private var selected: LedgerEntry?
    var month: String { Day.month(date) }
    var income: Int64 { store.ledger.total(.income, month: month) }
    var expense: Int64 { store.ledger.total(.expense, month: month) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("YOUR EVERYDAY, WELL KEPT").font(.system(size: 9)).tracking(2); Spacer(); Text("CAD").font(.caption2).padding(8).background(.white, in: Capsule()) }.foregroundStyle(HearthTheme.muted)
                VStack(alignment: .leading, spacing: 8) { Text("把生活，记在心上。").font(.system(size: 29, weight: .semibold, design: .rounded)); Text("小家的每一笔，都值得好好记录。").font(.footnote).foregroundStyle(HearthTheme.muted) }
                MonthPicker(date: $date)
                VStack(alignment: .leading, spacing: 24) {
                    Text("本月结余  /  MONTHLY BALANCE").font(.caption).foregroundStyle(.white.opacity(0.65))
                    Text(Money.text(income - expense)).font(.system(size: 38, weight: .medium, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1).monospacedDigit()
                    Divider().overlay(.white.opacity(0.15))
                    HStack { summary("arrow.down.left", "本月收入", income); Spacer(); summary("arrow.up.right", "本月支出", expense); Spacer(minLength: 0) }
                }.padding(25).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white).background(HearthTheme.green.gradient, in: RoundedRectangle(cornerRadius: 24))
                Button { add = true } label: { Label("记一笔", systemImage: "plus") }.buttonStyle(PrimaryButton())
                if let budget = store.ledger.budgets[month] {
                    HearthCard {
                        Text("本月预算").font(.headline)
                        HStack(alignment: .firstTextBaseline) { Text(Money.text(max(0, budget - expense))).font(.title2.weight(.medium)); Text("剩余").font(.caption).foregroundStyle(HearthTheme.muted) }
                        ProgressView(value: min(Double(expense) / Double(budget), 1)).tint(expense > budget ? .orange : HearthTheme.green)
                        Text(expense > budget ? "已超出预算 \(Money.text(expense - budget))" : "总预算 \(Money.text(budget)) · 给生活留一点余地").font(.caption).foregroundStyle(HearthTheme.muted)
                    }
                }
                HearthCard {
                    HStack { Text("最近的生活").font(.headline); Spacer(); Text("\(store.ledger.entries(in: month).count) 笔").font(.caption).foregroundStyle(HearthTheme.muted) }
                    if store.ledger.entries(in: month).isEmpty { EmptyLedger() }
                    ForEach(Array(store.ledger.entries(in: month).prefix(5))) { e in Button { selected = e } label: { EntryRow(entry: e) }.buttonStyle(.plain) }
                }
                Text("只记账，不焦虑。慢慢把日子过成喜欢的样子。").font(.caption2).foregroundStyle(HearthTheme.muted).frame(maxWidth: .infinity).padding(.vertical, 12)
            }.padding(22)
        }.background(HearthTheme.paper).navigationTitle("小家").navigationBarTitleDisplayMode(.inline).toolbar { Button { store.lock() } label: { Image(systemName: "lock") }.accessibilityLabel("锁定账本") }.sheet(item: $selected) { EntryEditor(existing: $0) }
    }
    private func summary(_ icon: String, _ title: String, _ value: Int64) -> some View { VStack(alignment: .leading, spacing: 10) { Label(title, systemImage: icon).font(.caption2).opacity(0.65); Text(Money.text(value)).font(.title3).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6) } }
}
struct RecordsView: View {
    @EnvironmentObject var store: VaultStore
    @State private var date = Date()
    @State private var search = ""
    @State private var filter = "all"
    @State private var add = false
    @State private var selected: LedgerEntry?
    var entries: [LedgerEntry] { store.ledger.entries(in: Day.month(date)).filter { e in
        (filter == "all" || (filter == "review" ? e.needsReview : e.kind.rawValue == filter)) && (search.isEmpty || "\(e.merchant) \(e.category.rawValue) \(e.note) \(e.member)".localizedCaseInsensitiveContains(search))
    } }
    var body: some View {
        List {
            Section { MonthPicker(date: $date).listRowBackground(HearthTheme.paper); Picker("记录类型", selection: $filter) { Text("全部").tag("all"); Text("支出").tag("expense"); Text("收入").tag("income"); Text("待核对").tag("review") }.pickerStyle(.segmented).listRowBackground(HearthTheme.paper) }
            Section("\(entries.count) 笔记录") {
                if entries.isEmpty { EmptyLedger() }
                ForEach(entries) { e in Button { selected = e } label: { EntryRow(entry: e) }.buttonStyle(.plain).swipeActions { Button(role: .destructive) { store.delete(e) } label: { Label("删除", systemImage: "trash") } } }
            }
        }.scrollContentBackground(.hidden).background(HearthTheme.paper).searchable(text: $search, prompt: "搜索商户、分类或备注").navigationTitle("收支明细").toolbar { Button { add = true } label: { Image(systemName: "plus") }.accessibilityLabel("新增记录") }.sheet(isPresented: $add) { EntryEditor() }.sheet(item: $selected) { EntryEditor(existing: $0) }
    }
}
struct EntryEditor: View {
    @EnvironmentObject var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    var existing: LedgerEntry?
    @State private var kind: EntryKind = .expense
    @State private var amount = ""
    @State private var merchant = ""
    @State private var date = Date()
    @State private var category: Category = .groceries
    @State private var member = "共同"
    @State private var account = "信用卡"
    @State private var note = ""
    @State private var confirmDelete = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section { Picker("类型", selection: $kind) { Text("支出").tag(EntryKind.expense); Text("收入").tag(EntryKind.income) }.pickerStyle(.segmented)
                    HStack(alignment: .firstTextBaseline) { Text("CAD").font(.caption).foregroundStyle(HearthTheme.muted); TextField("0.00", text: $amount).font(.system(size: 40, weight: .medium, design: .rounded)).keyboardType(.decimalPad) }
                    TextField("商户 / 收入来源", text: $merchant).textInputAutocapitalization(.words)
                }
                Section("生活的细节") {
                    DatePicker("交易日期", selection: $date, displayedComponents: .date)
                    Picker("分类", selection: $category) { ForEach(Category.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) } }
                    Picker("成员", selection: $member) { ForEach(["共同", "我", "家人"], id: \.self) { Text($0) } }
                    Picker("账户", selection: $account) { ForEach(["信用卡", "借记卡", "银行转账", "现金"], id: \.self) { Text($0) } }
                    TextField("备注（可选）", text: $note, axis: .vertical).lineLimit(2...4)
                }
                if existing?.needsReview == true { Section { Text("这笔由邮件识别。保存即表示你已核对金额、日期、商户和交易是否已入账。待核对的记录也计入总额。").font(.footnote).foregroundStyle(.orange) } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if existing != nil { Section { Button("删除这笔记录", role: .destructive) { confirmDelete = true } } }
            }.scrollContentBackground(.hidden).background(HearthTheme.paper).navigationTitle(existing == nil ? "记下这一笔" : "核对与编辑").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.fontWeight(.semibold) } }
                .confirmationDialog("删除后无法直接撤销。邮件记录不会再次自动导入。", isPresented: $confirmDelete, titleVisibility: .visible) { Button("删除记录", role: .destructive) { if let existing { store.delete(existing) }; dismiss() } }
                .onAppear { if let e = existing { kind = e.kind; amount = Money.editable(e.cents); merchant = e.merchant; date = Day.date(e.date) ?? Date(); category = e.category; member = e.member; account = e.account; note = e.note } }
        }
    }
    private func save() {
        do {
            var item = LedgerEntry(id: existing?.id ?? UUID().uuidString, kind: kind, cents: try Money.cents(amount), merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines), date: Day.string(date), category: category, member: member, account: account, note: note, sourceID: existing?.sourceID, needsReview: false)
            if item.kind == .income && item.category == .groceries { item.category = .salary }
            try item.validate(); try store.update { l in if let i = l.entries.firstIndex(where: { $0.id == item.id }) { l.entries[i] = item } else { l.entries.append(item) } }; dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
struct CategoryTotal: Identifiable { var category: Category; var cents: Int64; var id: String { category.rawValue } }
struct StatsView: View {
    @EnvironmentObject var store: VaultStore
    @State private var date = Date()
    @State private var budget = ""
    var month: String { Day.month(date) }
    var total: Int64 { store.ledger.total(.expense, month: month) }
    var groups: [CategoryTotal] { Category.allCases.map { c in CategoryTotal(category: c, cents: store.ledger.entries(in: month).filter { $0.kind == .expense && $0.category == c }.reduce(0) { $0 + $1.cents }) }.filter { $0.cents > 0 }.sorted { $0.cents > $1.cents } }
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                MonthPicker(date: $date)
                HearthCard {
                    Text("看懂支出，心里有底。").font(.headline)
                    if total == 0 { EmptyLedger() } else {
                        Chart(groups) { g in SectorMark(angle: .value("金额", g.cents), innerRadius: .ratio(0.73), angularInset: 2).cornerRadius(4).foregroundStyle(by: .value("分类", g.category.rawValue)) }.chartLegend(.hidden).chartForegroundStyleScale(range: HearthTheme.palette).frame(height: 210).overlay { VStack { Text("本月支出").font(.caption).foregroundStyle(HearthTheme.muted); Text(Money.text(total)).font(.title3.weight(.semibold)).monospacedDigit() } }
                        ForEach(groups) { g in HStack { Label(g.category.rawValue, systemImage: g.category.symbol); Spacer(); Text(Money.text(g.cents)).monospacedDigit(); Text("\(Int(Double(g.cents) / Double(total) * 100))%").foregroundStyle(HearthTheme.muted).frame(width: 42, alignment: .trailing) }.font(.subheadline) }
                    }
                }
                HearthCard {
                    Text("给本月设个小目标").font(.headline)
                    Text("每月预算独立保存，随时可以调整。").font(.caption).foregroundStyle(HearthTheme.muted)
                    TextField("月度预算 · CAD", text: $budget).keyboardType(.decimalPad).padding().background(HearthTheme.paper, in: RoundedRectangle(cornerRadius: 12))
                    Button("保存本月预算") { do { store.setBudget(try Money.cents(budget), month: month) } catch { store.message = error.localizedDescription } }.buttonStyle(PrimaryButton())
                }
                let pending = store.ledger.entries(in: month).filter(\.needsReview).count
                if pending > 0 { Text("本月包含 \(pending) 笔待核对邮件记录，已计入以上金额。").font(.footnote).foregroundStyle(.orange) }
            }.padding(22)
        }.background(HearthTheme.paper).navigationTitle("统计与预算").onAppear { loadBudget() }.onChange(of: month) { _, _ in loadBudget() }
    }
    private func loadBudget() { budget = store.ledger.budgets[month].map(Money.editable) ?? "3000.00" }
}
struct MailView: View {
    @EnvironmentObject var store: VaultStore
    @State private var text = ""
    @State private var parsed: LedgerEntry?
    @State private var importFile = false
    @State private var editKey = false
    @State private var keyInput = ""
    @State private var error: String?
    @State private var revealKey = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("邮件里，也藏着生活。").font(.title2.weight(.semibold))
                HearthCard {
                    Label("免费 Windows 邮件助手", systemImage: "desktopcomputer").font(.headline)
                    Text("电脑读取指定发件人的消费邮件，生成加密同步文件。将文件放进两端可访问的云盘，首次在这里选定。每次解锁或点击刷新时，App 读取文件并去重导入。").font(.footnote).foregroundStyle(HearthTheme.muted).lineSpacing(4)
                    Text(store.ledger.feedBookmark == nil ? "尚未选择同步文件" : "已选择文件 · 解锁后读取").font(.caption).foregroundStyle(store.ledger.feedBookmark == nil ? .orange : HearthTheme.green)
                    if store.ledger.syncKeyHex == nil { Button("生成配对密钥") { store.createSyncKey() }.buttonStyle(PrimaryButton()) }
                    else {
                        Button(revealKey ? "隐藏配对密钥" : "显示配对密钥") { revealKey.toggle() }
                        if revealKey { Text(store.ledger.syncKeyHex ?? "").font(.system(.caption, design: .monospaced)).textSelection(.enabled); Text("请仅在自己的 Windows 邮件助手中输入。不要上传至 GitHub、截图或发给他人。").font(.caption2).foregroundStyle(.orange) }
                        Button { importFile = true } label: { Label("选择加密同步文件", systemImage: "folder") }.buttonStyle(PrimaryButton())
                        if store.ledger.feedBookmark != nil { Button("立即同步") { store.refreshFeed() }; Button("断开文件连接", role: .destructive) { store.disconnectFeed() } }
                    }
                    Button("使用已有配对密钥") { editKey = true }
                    if let last = store.ledger.lastSync { Text("上次读取：\(last)").font(.caption2).foregroundStyle(HearthTheme.muted) }
                }
                HearthCard {
                    Text("也可以粘贴一封通知").font(.headline)
                    TextEditor(text: $text).frame(minHeight: 150).scrollContentBackground(.hidden).padding(8).background(HearthTheme.paper, in: RoundedRectangle(cornerRadius: 12)).accessibilityLabel("消费邮件内容")
                    Button("识别并核对") { do { parsed = try AlertParser.parse(text); error = nil } catch { self.error = error.localizedDescription } }.buttonStyle(PrimaryButton())
                    Button("填入示例（不会自动保存）") { text = "Your card ending 1234 was used at COSTCO for CAD 86.42 on \(Day.string(Date()))." }
                    if let error { Text(error).font(.footnote).foregroundStyle(.orange) }
                }
                Text("仅识别有明确 CAD 币种、单笔金额、商户和日期的消费通知。退款、还款、账单、多金额或不明确内容会跳过；并非所有银行格式都能自动识别。自动导入的记录需在明细中核对。iPhone 关闭 App 后不持续监控邮箱。").font(.footnote).foregroundStyle(HearthTheme.muted).lineSpacing(4)
            }.padding(22)
        }.background(HearthTheme.paper).navigationTitle("邮件记账")
            .fileImporter(isPresented: $importFile, allowedContentTypes: [.data, .json]) { result in do { store.selectFeed(try result.get()) } catch { store.message = "未选择文件。" } }
            .sheet(item: $parsed) { item in MailPreview(entry: item) }
            .sheet(isPresented: $editKey) { NavigationStack { Form { Section("来自另一设备的配对密钥") { SecureField("64 位十六进制密钥", text: $keyInput).textInputAutocapitalization(.never).autocorrectionDisabled(); Text("替换密钥后，旧密钥加密的文件将无法读取。").font(.footnote) } }.navigationTitle("配对密钥").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { editKey = false } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { do { _ = try FeedCrypto.key(keyInput); store.setSyncKey(keyInput); keyInput = ""; editKey = false } catch { store.message = error.localizedDescription } } } } } }
    }
}
struct MailPreview: View {
    @EnvironmentObject var store: VaultStore
    @Environment(\.dismiss) private var dismiss
    let entry: LedgerEntry
    var body: some View {
        NavigationStack { Form {
            Section("识别结果") { LabeledContent("商户", value: entry.merchant); LabeledContent("金额 CAD", value: Money.text(entry.cents)); LabeledContent("交易日期", value: entry.date); LabeledContent("分类", value: entry.category.rawValue) }
            Section { Text("导入后可在「明细 → 待核对」中编辑。重复邮件自动跳过。若内容不正确，请取消并手工记账。").font(.footnote); Button("导入账本") { store.merge([entry]); dismiss() } }
        }.navigationTitle("核对消费通知").toolbar { Button("取消") { dismiss() } } }
    }
}
struct HearthDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .json, .commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { guard let d = configuration.file.regularFileContents else { throw LedgerError.invalid("文件无法读取。") }; data = d }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct RestoreButton: View {
    @EnvironmentObject var store: VaultStore
    @State private var choose = false
    @State private var data: Data?
    @State private var password = ""
    @State private var restoreSheet = false
    @State private var confirm = false
    var body: some View {
        Button { choose = true } label: { Label("从加密备份恢复", systemImage: "arrow.counterclockwise") }
            .fileImporter(isPresented: $choose, allowedContentTypes: [.data, .json]) { result in
                do { let url = try result.get(); let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0; guard size <= 32_000_000 else { throw LedgerError.invalid("备份过大。") }
                    let bytes = try Data(contentsOf: url); _ = try VaultCrypto.read(bytes); data = bytes; restoreSheet = true
                } catch { store.message = "无法打开备份：\(error.localizedDescription)" }
            }
            .sheet(isPresented: $restoreSheet) {
                NavigationStack { Form {
                    Section("输入这份备份导出时的密码") { SecureField("备份密码", text: $password); Text("恢复会替换本机账本，不会合并。请先导出当前账本备份。恢复成功前原文件不会被替换。").font(.footnote).foregroundStyle(.orange) }
                    Button("验证并恢复", role: .destructive) { confirm = true }.disabled(password.isEmpty || store.busy)
                }.navigationTitle("恢复加密账本").toolbar { Button("取消") { restoreSheet = false; password = ""; data = nil } }
                    .confirmationDialog("确定用备份替换本机账本？", isPresented: $confirm, titleVisibility: .visible) { Button("替换并恢复", role: .destructive) { if let data { let p = password; password = ""; restoreSheet = false; Task { await store.restore(data, password: p) } } } }
                }
            }
    }
}
struct SettingsView: View {
    @EnvironmentObject var store: VaultStore
    @State private var document = HearthDocument(data: Data())
    @State private var exporting = false
    @State private var filename = ""
    @State private var exportType = UTType.data
    @State private var changePassword = false
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var repeated = ""
    @State private var confirmCSV = false
    var body: some View {
        Form {
            Section { Label("你的小家，你来打理。", systemImage: "leaf").font(.headline); LabeledContent("本机用户名", value: store.username); LabeledContent("记录数量", value: "\(store.ledger.entries.count) 笔"); Text("本机账号与账本。不会自动在家庭成员之间双向同步，也不是云端账户。").font(.footnote).foregroundStyle(HearthTheme.muted) }
            Section("安全与解锁") {
                if store.biometricsEnabled { Button("关闭 Face ID / Touch ID") { store.disableBiometrics() } }
                else { Button("启用 Face ID / Touch ID") { Task { await store.enableBiometrics() } } }
                Button("更改账本密码") { changePassword = true }
                Button("立即锁定") { store.lock() }
                Text("App 进入后台即锁定。生物识别改变后，请用账本密码解锁并重新启用 Face ID。密码遗失无法找回。").font(.footnote).foregroundStyle(HearthTheme.muted)
            }
            Section("备份与数据") {
                Button { do { document = HearthDocument(data: try store.backup()); filename = "Hearth-\(Day.string(Date())).hearth"; exportType = .data; exporting = true } catch { store.message = error.localizedDescription } } label: { Label("导出加密备份", systemImage: "lock.doc") }
                RestoreButton()
                Button { confirmCSV = true } label: { Label("导出 CSV", systemImage: "tablecells") }
                Text("建议每周备份。卸载 App 会移除账本；免费签名刷新时应覆盖安装，不要先卸载。导出的加密备份用导出时的账本密码解锁。").font(.footnote).foregroundStyle(HearthTheme.muted)
            }
            Section("关于免费安装") {
                Text("原生 SwiftUI · iOS 17 或更新版本").font(.subheadline)
                Text("通过免费 Apple 账号侧载，每 7 天需刷新签名。到期不代表账目被删除，请勿为刷新而卸载。保持同一 Apple 账号及 App 标识。").font(.footnote).foregroundStyle(HearthTheme.muted)
                Link("AltStore Classic 官方安装说明", destination: URL(string: "https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows")!)
            }
            Section { Text("小家 1.0 · 把生活，记在心上。\n无广告、无统计追踪。邮件原文不写入账本。所有自动识别结果都需要核对。").font(.caption).foregroundStyle(HearthTheme.muted) }
        }.scrollContentBackground(.hidden).background(HearthTheme.paper).navigationTitle("账本设置")
            .fileExporter(isPresented: $exporting, document: document, contentType: exportType, defaultFilename: filename) { result in if case .failure = result { store.message = "导出未完成，请重试。" } }
            .confirmationDialog("CSV 是未加密的账目文件，请只保存到可信位置。", isPresented: $confirmCSV, titleVisibility: .visible) { Button("导出未加密 CSV") { document = HearthDocument(data: Data(store.ledger.csv.utf8)); filename = "Hearth-\(Day.string(Date())).csv"; exportType = .commaSeparatedText; exporting = true } }
            .sheet(isPresented: $changePassword) { NavigationStack { Form {
                SecureField("当前密码", text: $oldPassword); SecureField("新密码（至少 10 个字符）", text: $newPassword); SecureField("再次输入新密码", text: $repeated)
                Button("保存新密码") { guard newPassword == repeated else { store.message = "两次新密码不一致。"; return }; let old = oldPassword, new = newPassword; oldPassword = ""; newPassword = ""; repeated = ""; changePassword = false; Task { await store.changePassword(old: old, new: new) } }.disabled(store.busy || newPassword.count < 10)
                Text("旧备份仍使用导出时的旧密码，修改后请重新备份。").font(.footnote)
            }.navigationTitle("更改密码").toolbar { Button("取消") { changePassword = false; oldPassword = ""; newPassword = ""; repeated = "" } } } }
    }
}
