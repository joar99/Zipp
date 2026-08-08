// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ZippData",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "ZippData", targets: ["ZippData"]),
    ],
    dependencies: [
        .package(path: "../ZippFoundation"),
        .package(path: "../ZippNetworking"),
    ],
    targets: [
        .target(name: "ZippData", dependencies: ["ZippFoundation", "ZippNetworking"]),
    ]
)
