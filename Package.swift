// swift-tools-version: 5.9
import PackageDescription
var products: [Product] = [.library(name: "ArkivCore", targets: ["ArkivCore"])]
var targets: [Target] = [
    .target(name: "CArkiv", linkerSettings: [.linkedLibrary("archive")]),
    .target(name: "ArkivCore", dependencies: ["CArkiv"]),
    .testTarget(name: "ArkivCoreTests", dependencies: ["ArkivCore"]),
    .target(name: "ArkivPresentation", dependencies: ["ArkivCore"]),
    .testTarget(name: "ArkivPresentationTests", dependencies: ["ArkivPresentation"])
]
#if os(macOS)
products.append(.executable(name: "Arkiv", targets: ["ArkivApp"]))
targets.append(.executableTarget(name: "ArkivApp", dependencies: ["ArkivCore", "ArkivPresentation"]))
targets.append(.testTarget(name: "ArkivAppTests", dependencies: ["ArkivApp"]))
#endif
let package = Package(name: "Arkiv", platforms: [.macOS(.v13)], products: products, targets: targets)
