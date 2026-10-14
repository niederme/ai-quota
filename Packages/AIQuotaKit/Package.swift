// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIQuotaKit",
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
