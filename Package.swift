// swift-tools-version: 5.9
import PackageDescription
var dependencies: [Package.Dependency] = []
var products: [Product] = [.library(name: "ArkivCore", targets: ["ArkivCore"])]
// Pin Apple system decoders instead of letting -l search runner-local/Homebrew
// libraries. ld resolves these absolute system inputs through the selected SDK.
var compressionLibraries: [LinkerSetting] = [.linkedLibrary("z"), .linkedLibrary("bz2"), .linkedLibrary("lzma")]
#if os(macOS)
compressionLibraries = [.unsafeFlags([
    "-Xlinker", "/usr/lib/libz.1.dylib",
    "-Xlinker", "/usr/lib/libbz2.1.0.dylib",
    "-Xlinker", "/usr/lib/liblzma.5.dylib"
])]
#endif
var targets: [Target] = [
    .target(name: "ArkivFinderIntegration"),
    .testTarget(name: "ArkivFinderIntegrationTests", dependencies: ["ArkivFinderIntegration"]),
    .target(name: "CArkiv", cSettings: [.headerSearchPath("vendor/xz")], linkerSettings: compressionLibraries + [.linkedLibrary("archive"), .linkedLibrary("ArkivSeven")]),
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
