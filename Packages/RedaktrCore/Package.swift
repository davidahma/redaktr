// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RedaktrCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RedaktrCore", targets: ["RedaktrCore"])
    ],
    targets: [
        .target(name: "RedaktrCore"),
        .testTarget(name: "RedaktrCoreTests", dependencies: ["RedaktrCore"])
    ]
)
