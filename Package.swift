// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AppSleuth",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "AppSleuthCore", targets: ["AppSleuthCore"]),
        .executable(name: "appsleuth", targets: ["AppSleuth"])
    ],
    targets: [
        .target(name: "AppSleuthCore"),
        .executableTarget(
            name: "AppSleuth",
            dependencies: ["AppSleuthCore"]
        ),
        .testTarget(
            name: "AppSleuthCoreTests",
            dependencies: ["AppSleuthCore"]
        )
    ]
)
