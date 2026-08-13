import SwiftUI

// AppDelegate muss supportedInterfaceOrientationsFor implementieren,
// damit SwiftUI WindowGroup-Apps auf iPhones wirklich rotieren.
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return .allButUpsideDown
    }
}

@main
struct DemonicMusicDashboardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            AppTabView()
        }
    }
}
