// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ZippFoundation",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "ZippFoundation", targets: ["ZippFoundation"]),
    ],
    targets: [
        .target(name: "ZippFoundation", dependencies: []),
    ]
)
