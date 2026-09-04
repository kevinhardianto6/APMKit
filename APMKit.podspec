Pod::Spec.new do |s|
  s.name         = "APMKit"
  s.version      = "0.0.3"
  s.summary      = "In-house iOS Application Performance Monitoring SDK — crash reporting and network observability."
  s.homepage     = "https://github.com/kevinhardianto6/APMKit"
  s.license      = { :type => "Proprietary", :text => "Internal use only — not for public distribution." }
  s.author       = { "Mobile Platform Team" => "hardiantokevin00@gmail.com" }

  # docs/02-Mobile-SDK.md: iOS 15+. This podspec has no s.osx line — unlike Package.swift,
  # which also declares .macOS(.v11) *only* so `swift build`/`swift test` see iOS-15-era API
  # availability on the host toolchain (CONSTITUTION.md platform invariants) — the SDK itself
  # only ever ships on iOS, and CocoaPods integrators are always building for a real platform
  # target, not a host-toolchain check, so there's no equivalent reason to declare macOS here.
  s.ios.deployment_target = "15.0"
  s.swift_versions = ["5.9"]

  s.source       = { :git => "https://github.com/kevinhardianto6/APMKit.git", :tag => s.version.to_s }
  s.source_files = "Sources/APMKit/**/*.swift"

  # Mirrors Package.swift's `.package(url: ".../KSCrash.git", from: "2.1.0")` dependency on
  # product "Recording" exactly — VERSIONING.md documents these two manifests (this podspec
  # and Package.swift) as a pair that must be kept in sync by hand; nothing enforces it
  # automatically, unlike the SDKInfo-version check (Tests/APMKitTests/VersioningTests.swift).
  s.dependency "KSCrash/Recording", ">= 2.1.0"

  s.pod_target_xcconfig = { "DEFINES_MODULE" => "YES" }
end
