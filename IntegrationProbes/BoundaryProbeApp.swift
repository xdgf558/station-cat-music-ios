import SwiftUI
import Darwin

// Simulator-only test application. Not part of any product target or archive.
@main struct BoundaryProbeApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Isolated recovery probe").task {
                do {
                    let config = try CrashProbeConfiguration.load()
                    let scenario = NativeCrashScenario()
                    if config.mode == "CRASH" {
                        try await scenario.testCrashAtRefreshBoundary()
                    } else {
                        try await scenario.testRecoverOriginalOperation()
                    }
                    fflush(nil)
                    _exit(0)
                } catch {
                    print("M2_PROBE_FAILED: \(error)")
                    fflush(nil)
                    _exit(1)
                }
            }
        }
    }
}
