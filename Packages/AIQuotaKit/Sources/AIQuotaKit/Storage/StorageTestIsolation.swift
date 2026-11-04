import Foundation

/// SwiftPM's Swift Testing runner loads test libraries without an .xctest bundle.
/// Keep all test stores isolated for both supported native test hosts.
enum StorageTestIsolation {
    static var isRunningTests: Bool {
        Bundle.allBundles.contains { $0.bundlePath.hasSuffix(".xctest") }
            || URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent == "swiftpm-testing-helper"
    }

    /// A test runner may retain a fresh UUID namespace across child processes.
    /// Production executables cannot opt into test storage through this value.
    static var identifier: String {
        if isRunningTests,
           let value = ProcessInfo.processInfo.environment["AIQUOTA_TEST_STORE_ID"],
           let id = UUID(uuidString: value) { return id.uuidString.lowercased() }
        return String(ProcessInfo.processInfo.processIdentifier)
    }

}
