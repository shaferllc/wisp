// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Wisp",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Free shafer.llc registration, Help and Contact Support.
        .package(url: "https://github.com/shaferllc/swift-licensing", from: "1.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "Wisp",
            dependencies: [.product(name: "ShaferAccount", package: "swift-licensing")],
            path: "Sources/Wisp"
        ),
        .testTarget(
            name: "WispTests",
            dependencies: ["Wisp"],
            path: "Tests/WispTests"
        ),
    ]
)
