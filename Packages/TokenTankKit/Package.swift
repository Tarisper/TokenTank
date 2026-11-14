// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenTankKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TokenTankKit", targets: ["TokenTankKit"]),
        .library(name: "TokenTankWidgetUI", targets: ["TokenTankWidgetUI"]),
    ],
    targets: [
        .target(name: "TokenTankKit"),
        .target(
            name: "TokenTankWidgetUI",
            dependencies: ["TokenTankKit"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "TokenTankKitTests",
            dependencies: ["TokenTankKit", "TokenTankWidgetUI"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
