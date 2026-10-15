// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SKICE_CS",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // An xtool project should contain exactly one library product,
        // representing the main app.
        .library(
            name: "SKICE_CS",
            targets: ["SKICE_CS"]
        ),
    ],
    targets: [
        .target(
            name: "SKICE_CS",
            path: "Sources/SKICE_CS"
        ),
    ]
)
