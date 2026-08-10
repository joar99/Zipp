// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ZippFoundation",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "ZippFoundation", targets: ["ZippFoundation"]),
    ],
    targets: [
        .target(
            name: "ZippFoundation",
            dependencies: [],
            // The platform-to-lines mapping, derived at build time by
            // Tools/generate_lines.py because GTFS will not state it directly.
            resources: [.process("Resources")]
        ),
    ]
)
