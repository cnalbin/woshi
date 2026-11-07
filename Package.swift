// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QingJiCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "QingJiCore", targets: ["QingJiCore"])],
    targets: [
        .target(name: "QingJiCore", path: "ios/Core"),
        .testTarget(name: "QingJiCoreTests", dependencies: ["QingJiCore"], path: "ios/CoreTests")
    ]
)
