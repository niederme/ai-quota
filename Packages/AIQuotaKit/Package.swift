// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIQuotaKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AIQuotaKit", targets: ["AIQuotaKit"])
    ],
    dependencies: [.package(path: "../MobileAccessCore")],
    targets: [
        .target(
            name: "AIQuotaKit",
            dependencies: ["MobileAccessCore"],
            path: "Sources/AIQuotaKit",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("AppKit"),
            ]
        ),
        .testTarget(
            name: "AIQuotaKitTests",
            dependencies: ["AIQuotaKit"],
            path: "Tests/AIQuotaKitTests",
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("AppKit"),
            ]
        )
    ]
)
