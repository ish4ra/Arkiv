// swift-tools-version: 5.9
import PackageDescription
var dependencies: [Package.Dependency] = []
var products: [Product] = [.library(name: "ArkivCore", targets: ["ArkivCore"])]
var targets: [Target] = [
    .target(name: "ArkivFinderIntegration"),
    .testTarget(name: "ArkivFinderIntegrationTests", dependencies: ["ArkivFinderIntegration"]),
    .target(name: "CArkiv", linkerSettings: [.linkedLibrary("archive"), .linkedLibrary("ArkivSeven")]),
    .target(name: "ArkivCore", dependencies: ["CArkiv", "ArkivFinderIntegration"]),
    .testTarget(name: "ArkivCoreTests", dependencies: ["ArkivCore"]),
    .target(name: "ArkivPresentation", dependencies: ["ArkivCore"]),
    .testTarget(name: "ArkivPresentationTests", dependencies: ["ArkivPresentation"])
]
#if os(macOS)
dependencies.append(.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"))
products.append(.executable(name: "Arkiv", targets: ["ArkivApp"]))
targets.append(.executableTarget(name: "ArkivApp", dependencies: ["ArkivCore", "ArkivPresentation", "ArkivFinderIntegration", .product(name: "Sparkle", package: "Sparkle")],
    linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]))
targets.append(.testTarget(name: "ArkivAppTests", dependencies: ["ArkivApp"]))
#endif
let package = Package(name: "Arkiv", platforms: [.macOS(.v13)], products: products, dependencies: dependencies, targets: targets)
