// swift-tools-version: 5.9
import PackageDescription

// Not the SDK itself — AGENTS.md is explicit that the SDK repo has "no app target." This is
// CI-only measurement tooling (feat-012, docs/02 §5): two minimal executables, one that links
// APMKit and one that doesn't, so `check-binary-size-budget.sh` can measure the *delta* a real
// consuming app would actually pay for adding this SDK — an "automatic" library product (see
// ../../Package.swift) has no final linked artifact of its own to measure directly; only a
// consumer does.
let package = Package(
    name: "size-budget",
    platforms: [.macOS(.v11)],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        // No APMKit import — the baseline every delta is measured against.
        .executableTarget(name: "Baseline"),
        // Links APMKit and touches a real symbol so the linker can't dead-strip the import
        // away entirely.
        .executableTarget(name: "WithSDK", dependencies: [.product(name: "APMKit", package: "APMKit")])
    ]
)
