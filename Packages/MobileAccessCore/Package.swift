// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "MobileAccessCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "MobileAccessCore", targets: ["MobileAccessCore"])],
    targets: [.target(name: "MobileAccessCore", resources: [.process("Resources")]),
              .testTarget(name: "MobileAccessCoreTests", dependencies: ["MobileAccessCore"])]
)
