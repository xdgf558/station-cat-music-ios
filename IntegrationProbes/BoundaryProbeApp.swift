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
        Task { @MainActor in
            do {
                let config = try CrashProbeConfiguration.load()
                try ProbeReporter.emit("M2_PROBE_STARTED:\(config.stage):\(config.mode):pid=\(getpid())")
                let scenario = NativeCrashScenario()
                if config.mode == "CRASH" { try await scenario.testCrashAtRefreshBoundary() }
                else { try await scenario.testRecoverOriginalOperation() }
                try ProbeReporter.emit("M2_PROBE_FINISHED:\(config.stage):\(config.mode):pid=\(getpid())")
                _exit(0)
            } catch {
                // Error details must not serialize request bodies or credentials into artifacts.
                try? ProbeReporter.emit("M2_PROBE_FAILED:pid=\(getpid())")
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
