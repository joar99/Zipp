// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ZippiOS",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "ZippiOS", targets: ["ZippiOS"]),
    ],
    dependencies: [
        .package(path: "../ZippNavigation"),
        .package(path: "../ZippFoundation"),
        .package(path: "../ZippData"),
    ],
    targets: [
        .target(name: "ZippiOS", dependencies: ["ZippNavigation", "ZippFoundation", "ZippData"]),
    ]
)
