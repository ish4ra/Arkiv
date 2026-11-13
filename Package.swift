// swift-tools-version: 5.9
import PackageDescription
var dependencies: [Package.Dependency] = []
var products: [Product] = [.library(name: "ArkivCore", targets: ["ArkivCore"])]
// Pin Apple SDK decoder stubs instead of letting -l search runner-local/Homebrew
// libraries or depending on linker-specific rewriting of absolute /usr/lib paths.
var compressionLibraries: [LinkerSetting] = [.linkedLibrary("z"), .linkedLibrary("bz2"), .linkedLibrary("lzma")]
#if os(macOS)
import Foundation
let sdkQuery = Process()
sdkQuery.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
sdkQuery.arguments = ["--sdk", "macosx", "--show-sdk-path"]
let sdkOutput = Pipe()
sdkQuery.standardOutput = sdkOutput
try sdkQuery.run()
let sdkData = sdkOutput.fileHandleForReading.readDataToEndOfFile()
sdkQuery.waitUntilExit()
let sdk = String(decoding: sdkData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
precondition(sdkQuery.terminationStatus == 0 && !sdk.isEmpty, "Select an installed macOS SDK with xcode-select.")
let decoderStubs = ["libz.1", "libbz2.1.0", "liblzma.5"].map { sdk + "/usr/lib/" + $0 + ".tbd" }
precondition(decoderStubs.allSatisfy { FileManager.default.fileExists(atPath: $0) }, "The selected macOS SDK must provide all system decoder stubs.")
compressionLibraries = [.unsafeFlags(decoderStubs.flatMap { ["-Xlinker", $0] })]
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
