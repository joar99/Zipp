// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ZippNetworking",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "ZippNetworking", targets: ["ZippNetworking"]),
    ],
    dependencies: [
        .package(path: "../ZippFoundation"),
    ],
    targets: [
        .target(name: "ZippNetworking", dependencies: ["ZippFoundation"]),
    ]
)
