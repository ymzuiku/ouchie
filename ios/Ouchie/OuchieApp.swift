import SwiftUI
import AppShell

@main
struct OuchieApp: App {
    init() {
        // No remote server — always re-extract the bundled client so updates take effect immediately.
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent("appshell_client"))
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(config: .init(
                serverURL: "",
                bundledZip: Bundle.main.url(forResource: "client", withExtension: "zip"),
                adapters: [
                    MotionAdapter(),
                    HapticAdapter(),
                    SettingsAdapter()
                ],
                devMode: true
            ))
        }
    }
}
