// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MenuMateCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [.library(name: "MenuMateCore", targets: ["MenuMateCore"])],
    targets: [
        .target(name: "MenuMateCore", resources: [.process("Localizable.xcstrings")]),
        .testTarget(name: "MenuMateCoreTests", dependencies: ["MenuMateCore"],
                    resources: [.copy("Fixtures")]),
    ]
)
