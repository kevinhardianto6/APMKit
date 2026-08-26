// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "APMKit",
    platforms: [
        .iOS(.v15),
        // Not a distribution target — the SDK only ships on iOS. This exists solely so
        // `swift build`/`swift test` on the host macOS toolchain sees iOS-15-era API
        // availability (e.g. Network's tls_protocol_version_t, macOS 10.15+) instead of an
        // old default floor. See CONSTITUTION.md platform invariants.
        .macOS(.v11)
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
