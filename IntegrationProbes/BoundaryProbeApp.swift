import UIKit
import Darwin

// Simulator-only test application. Never part of a product target or archive.
// Start from application launch, independent of SwiftUI view/task presentation.
@main final class BoundaryProbeApp: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Probe", sessionRole: connectingSceneSession.role)
        config.delegateClass = BoundaryProbeScene.self
        return config
    }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        do { try ProbeReporter.lifecycle(.delegateEntered) }
        catch { try? ProbeReporter.failure(error); _exit(1) }
        Task { @MainActor in
            do {
                try ProbeReporter.lifecycle(.scenarioTaskEntered)
                let config = try CrashProbeConfiguration.load()
                // A very fast _exit during launch can make the simulator launch
                // another host before simctl returns its PID. Do not touch the
                // fixture/Keychain until that exact launch has been acknowledged.
                try ProbeReporter.phase(.launchPermit)
                let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                try await ProbeLaunchPermit.wait(
                    runID: ProcessInfo.processInfo.environment["M2_PROBE_RUN_ID"] ?? "",
                    stage: config.stage, mode: config.mode, directory: directory)
                try ProbeReporter.emit("M2_PROBE_STARTED:\(config.stage):\(config.mode):pid=\(getpid())")
                let scenario = NativeCrashScenario()
                if config.mode == "CRASH" { try await scenario.testCrashAtRefreshBoundary() }
                else { try await scenario.testRecoverOriginalOperation() }
                try ProbeReporter.emit("M2_PROBE_FINISHED:\(config.stage):\(config.mode):pid=\(getpid())")
                _exit(0)
            } catch {
                // Error details must not serialize request bodies or credentials into artifacts.
                try? ProbeReporter.failure(error)
                _exit(1)
            }
        }
        return true
    }
}

final class BoundaryProbeScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController(); window.makeKeyAndVisible(); self.window = window
    }
}
