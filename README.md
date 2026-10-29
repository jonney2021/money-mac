# 小家 · 原生 iPhone 家庭账本

SwiftUI 原生 iOS App，暖白与深绿界面。免费 Apple 账号侧载路线：Windows + GitHub macOS 构建 + AltStore Classic。**源码不等于已验证的安装包，先查看 Actions 的实际构建状态。**

## 已实现的代码

- 本机用户名/密码注册登录，密码不少于 10 字符。
- AES-256-GCM 加密账本；PBKDF2-HMAC-SHA256（600,000 次）派生密码包装密钥；生物识别钥匙串解锁。
- Face ID / Touch ID、进入后台锁定、任务切换界面隐私遮挡。
- 收入/支出、分类、成员、账户、搜索、每月预算与环形统计。
- 加密备份与恢复、密码更改、CSV 导出（导出前提示未加密）。
- 单封消费通知粘贴识别，明确 CAD/商户/交易日期/单一金额才接受。
- Windows 邮件助手：Outlook Graph OAuth 或 Gmail IMAP 应用专用密码；发件人精确白名单；只读邮箱。
- Windows 生成 AES-GCM 加密同步文件；iPhone 用户选定文件后，在解锁/手动刷新时导入。
- 邮件去重、待核对标记，以及删除邮件账目后的去重墓碑。

## 首版边界

- 用户名密码是**单设备本机账号**，不是在线账号；没有云端密码找回和家庭多人双向账本同步。
- iPhone App 不会全天后台读取邮箱；电脑助手必须运行。云盘需要将同步文件实际下载至设备。同步文件访问权限、Face ID 与安装要在真机验证。
- 邮件格式采用保守通用规则，不保证支持全部银行。没有明确交易日期、只有 `$` 无币种、含账单/退款/还款/待处理或多个金额会跳过；不会把信用卡账单总额再计为消费。
- 导入的邮件账目先标记待核对，并计入统计。请核对后保存或删除；删除后不会重新导入。
- 免费签名通常每 7 天要刷新；不要为了刷新而卸载 App。保持同一 Apple 账号和 bundle ID。每周导出加密备份。
- 没有支付、银行交易或网银访问功能；邮箱权限不等于银行权限。

## 先生成 IPA

1. 将本仓库设为 **Public**，使用 GitHub 标准 macOS runner（勿开启付费 larger runner）。
2. 打开 **Actions → Build iPhone App → Run workflow**，选择默认分支运行；代码 push 到 `main` 或 `master` 也会构建。
3. 工作流依次运行 Swift 核心/加密测试、邮件助手 Python 测试，以及 `xcodebuild` 真正的 iOS 设备构建。
4. 只有全部绿色通过后，下载该次运行底部 **Artifacts → Hearth-iPhone-unsigned**。
5. 解压得到 `Hearth-unsigned.ipa`。这是**未签名设备安装包**，不可直接点 Safari 安装；下一步用你自己的免费 Apple 账号在本地签名。

标准 macOS runner 的公开仓库计费说明：https://docs.github.com/en/actions/reference/runners/github-hosted-runners

## Windows 安装到 iPhone

完整步骤见 [Docs/安装与使用.md](Docs/安装与使用.md)。

- 先按 AltStore Classic 的 Windows 官方文档安装 AltServer、Apple 驱动及配套组件：https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows
- Apple 账号密码只在你自己的本地 AltServer/Apple 官方界面输入；不要放进 GitHub Secrets、配置文件或发给开发者。
- 连接 iPhone，在 iPhone 上信任电脑，根据系统提示启用开发者模式，安装 AltStore Classic。
- 将 `Hearth-unsigned.ipa` 保存到 iPhone 的「文件」App，再在 AltStore 的 My Apps 中用 `+` 选择文件，由 AltServer 签名安装。
- 每周在 AltStore 使用 Refresh All。电脑 AltServer 与 iPhone 同一网络或 USB 连接更可靠，后台自动刷新不是保证。

## 邮件助手

先把 App 安装好，再阅读 [Docs/邮件同步.md](Docs/邮件同步.md)。尚未授权任何真实邮箱，配置完成并实测后才可确认可用。

## 项目结构与开发

```text
Sources/                 SwiftUI、账本逻辑与加密存储
Tests/HearthCoreTests/   Swift 核心、加密、跨语言同步测试
Companion/              Windows 邮件助手、配置样本、单元测试
Scripts/                纯 Python Xcode 项目生成与构建脚本
Resources/              App 图标、Info.plist、隐私声明
.github/workflows/      macOS 云端测试与 unsigned IPA 构建
```

不依赖 XcodeGen、CocoaPods 或 npm。iOS 17+，Xcode 16+。项目可由 `python Scripts/generate_project.py` 重新生成。

本地 macOS 验证：

```bash
swift test
bash Scripts/build_ios.sh
```

Python 邮件测试（无需邮箱）：

```bash
python -m pip install 'cryptography>=44,<51'
python -m unittest discover -s Companion -p 'test_*.py' -v
```

## 安全与备份

不上传真实账目到代码仓库。`.hearth` 备份包含加密账本和密码包装后的密钥，**用户名以明文存于备份头部**；账目、邮件配对密钥和同步文件书签均加密。旧备份需要导出时的旧密码。Face ID 密钥不随备份迁移，恢复后需重新开启。

没有遥测、广告和外部 SDK。Windows 凭据由 Credential Manager / DPAPI 保护，邮件原文不写入同步文件，Windows 历史也加密。发件人白名单不是反欺诈保证；识别结果仍需人工核对。邮件文件不是多人双向同步协议，不能用来替代整本账本备份。

本项目尚需在你的设备上验证签名安装、Face ID、文件书签及真实银行通知；不能仅凭源码或单元测试视为全部实机功能已通过。
