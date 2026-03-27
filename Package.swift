// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Hamstash",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "Hamstash",
            targets: ["Hamstash"]
        ),
    ],
    targets: [
        .target(
            name: "Hamstash"
        ),
        .testTarget(
            name: "HamstashTests",
            dependencies: ["Hamstash"]
        ),
    ]
)
