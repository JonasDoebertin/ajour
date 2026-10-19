// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SimpleLoginKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SimpleLoginKit", targets: ["SimpleLoginKit"]),
    ],
    targets: [
        .target(name: "SimpleLoginKit"),
        .testTarget(name: "SimpleLoginKitTests", dependencies: ["SimpleLoginKit"]),
    ]
)
