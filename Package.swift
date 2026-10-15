// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SKICE_CS",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "SKICE_CS",
            targets: ["SKICE_CS"]
        )
    ],
    targets: [
        .target(
            name: "SKICE_CS",
            path: "Sources/SKICE_CS"
        )
    ]
)