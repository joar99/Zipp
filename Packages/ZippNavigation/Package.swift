// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ZippNavigation",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ZippNavigation", targets: ["ZippNavigation"]),
    ],
    targets: [
        .target(name: "ZippNavigation", dependencies: []),
    ]
)
