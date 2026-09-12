// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "MobileAccessCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "MobileAccessCore", targets: ["MobileAccessCore"])],
    targets: [.target(name: "MobileAccessCore"),
              .testTarget(name: "MobileAccessCoreTests", dependencies: ["MobileAccessCore"])]
)
