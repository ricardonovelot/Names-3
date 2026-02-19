import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Diagnostics.log("AppDelegate didFinishLaunching")
        logSceneSnapshot(tag: "didFinishLaunching")
        return true
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        Diagnostics.log("AppDelegate willEnterForeground")
        logSceneSnapshot(tag: "willEnterForeground")
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Diagnostics.log("AppDelegate didBecomeActive")
        logSceneSnapshot(tag: "didBecomeActive")
    }

    func applicationWillResignActive(_ application: UIApplication) {
        Diagnostics.log("AppDelegate willResignActive")
        logSceneSnapshot(tag: "willResignActive")
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Diagnostics.log("AppDelegate didEnterBackground")
        logSceneSnapshot(tag: "didEnterBackground")
    }

    private func logSceneSnapshot(tag: String) {
        let scenes = UIApplication.shared.connectedScenes
        let described = scenes.compactMap { s -> String? in
            guard let ws = s as? UIWindowScene else { return nil }
            let windows = ws.windows
            let keyCount = windows.filter { $0.isKeyWindow }.count
            return String(format: "scene[%@] active=%@ activation=%ld windows=%d key=%d",
                          ws.session.persistentIdentifier,
                          ws.activationState == .foregroundActive ? "true" : "false",
                          ws.activationState.rawValue,
                          windows.count,
                          keyCount)
        }.joined(separator: " | ")
        Diagnostics.log("SceneSnapshot[\(tag)]: \(described)")
    }
}