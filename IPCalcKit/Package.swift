// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IPCalcKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "IPCalcKit", targets: ["IPCalcKit"]),
    ],
    targets: [
        .target(name: "IPCalcKit"),
        .testTarget(name: "IPCalcKitTests", dependencies: ["IPCalcKit"]),
    ]
)
