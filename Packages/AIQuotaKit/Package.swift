// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AIQuotaKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AIQuotaKit", targets: ["AIQuotaKit"])
    ],
    targets: [
        .target(
            name: "AIQuotaKit",
            dependencies: [],
            path: "Sources/AIQuotaKit",
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("AppKit"),
            ]
        )
    ]
)
