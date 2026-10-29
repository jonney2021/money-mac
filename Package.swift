// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "HearthCore", platforms: [.macOS(.v13), .iOS(.v17)], products: [.library(name: "HearthCore", targets: ["HearthCore"])], targets: [
    .target(name: "HearthCore", path: "Sources", exclude: ["HearthApp.swift", "Vault.swift", "Views.swift"], sources: ["HearthCore.swift", "VaultCrypto.swift"]),
    .testTarget(name: "HearthCoreTests", dependencies: ["HearthCore"], path: "Tests/HearthCoreTests")
])
