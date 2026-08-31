import Foundation

/// `Data.contains(_ other: Data)` (subsequence search) is iOS 16+ only — this SDK's floor is
/// iOS 15 (`Package.swift`). Caught by actually building `IOSDiskEncryptionHarnessTests`
/// against a real iOS Simulator target: it compiled fine on the macOS host (a different
/// platform/OS-version availability table) but failed for real against the iOS 15 floor.
/// `NSData.range(of:)` is the pre-iOS-16-compatible equivalent.
func dataContains(_ haystack: Data, _ needle: Data) -> Bool {
    let fullRange = NSRange(location: 0, length: haystack.count)
    return (haystack as NSData).range(of: needle, options: [], in: fullRange).location != NSNotFound
}
