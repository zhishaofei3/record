// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Record",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "RecordCore", targets: ["RecordCore"]),
        .executable(name: "RecordApp", targets: ["RecordApp"])
    ],
    targets: [
        .target(
            name: "RecordCore",
            path: "Sources/RecordCore"
        ),
        .executableTarget(
            name: "RecordApp",
            dependencies: ["RecordCore"],
            path: "Sources/RecordApp"
        ),
        .testTarget(
            name: "RecordCoreTests",
            dependencies: ["RecordCore"],
            path: "Tests/RecordCoreTests"
        )
    ]
)
