// swift-tools-version: 5.9
import PackageDescription
var products: [Product] = [.library(name: "ArkoCore", targets: ["ArkoCore"])]
var targets: [Target] = [
    .target(name: "CArko", linkerSettings: [.linkedLibrary("archive")]),
    .target(name: "ArkoCore", dependencies: ["CArko"]),
    .testTarget(name: "ArkoCoreTests", dependencies: ["ArkoCore"])
]
#if os(macOS)
products.append(.executable(name: "Arko", targets: ["ArkoApp"]))
targets.append(.executableTarget(name: "ArkoApp", dependencies: ["ArkoCore"]))
#endif
let package = Package(name: "Arko", platforms: [.macOS(.v13)], products: products, targets: targets)
