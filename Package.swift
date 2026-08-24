// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "APMKit",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "APMKit", targets: ["APMKit"])
    ],
    targets: [
        .target(
            name: "APMKit",
            path: "Sources/APMKit"
        ),
        .testTarget(
            name: "APMKitTests",
            dependencies: ["APMKit"],
            path: "Tests/APMKitTests"
        )
    ]
)
