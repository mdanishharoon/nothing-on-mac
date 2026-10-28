// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "nothing-on-mac",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "HeadphoneProtocol"),
        .executableTarget(name: "NothingOnMac", dependencies: ["HeadphoneProtocol"]),
        .testTarget(name: "HeadphoneProtocolTests", dependencies: ["HeadphoneProtocol"]),
    ]
)
