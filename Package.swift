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
    dependencies: [
        // feat-009: the only dependency Phase 2 is permitted to add (CONSTITUTION.md platform
        // invariants) — wraps a mature crash library instead of hand-rolling signal/mach
        // handlers (docs/02 §3.5).
        .package(url: "https://github.com/kstenerud/KSCrash.git", from: "2.1.0")
    ],
    targets: [
        .target(
            name: "APMKit",
            dependencies: [
                // Product name is "Recording" (unprefixed); the Swift module it vends is
                // `KSCrashRecording` — see KSCrash's own module-naming convention.
                .product(name: "Recording", package: "KSCrash")
            ],
            path: "Sources/APMKit"
        ),
        .testTarget(
            name: "APMKitTests",
            dependencies: ["APMKit"],
            path: "Tests/APMKitTests"
        )
    ]
)
