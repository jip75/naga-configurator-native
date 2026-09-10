import SwiftUI

@main
struct NagaConfiguratorApp: App {
    @StateObject private var hid = NagaHIDManager()
    @AppStorage("appearance") private var appearance: AppAppearance = .dark

    // App Nap throttles a LaunchServices-launched process's main run loop when it isn't the
    // key window — confirmed via `ps`: PRI 4 when launched normally vs PRI 46 launched from a
    // shell. That drop is enough for the CGEventTap's swallow callback to lose the race against
    // the system's default HID handling (button 10 leaking "0" alongside Mission Control).
    // Holding this activity for the process lifetime opts the whole app out of Nap.
    private static let appNapAssertion = ProcessInfo.processInfo.beginActivity(
        options: [.userInitiated, .idleSystemSleepDisabled],
        reason: "Continuous low-latency HID input monitoring for mouse button remapping"
    )

    init() {
        _ = Self.appNapAssertion
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(hid)
                .environment(\.appAppearance, $appearance)
                .frame(minWidth: 620, minHeight: 640)
                .background(Theme.bg)
                .preferredColorScheme(appearance.colorScheme)
                .onAppear {
                    hid.start()
                    #if DEBUG
                    // Manual DPI-write verification hook — NOT UI-wired on purpose (see
                    // NagaDPIWriter.swift for why this is still unverified against real hardware).
                    // TCC (Input Monitoring) is granted per signed app bundle, so run it through
                    // the built .app, not a bare `swift run` binary, e.g.:
                    //   NAGA_TEST_DPI=1600 build/NagaConfigurator.app/Contents/MacOS/NagaConfigurator
                    // Results go to stdout / Console.app, one line per HID interface the mouse exposes.
                    if let raw = ProcessInfo.processInfo.environment["NAGA_TEST_DPI"], let dpi = Int(raw) {
                        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1) {
                            let attempts = RazerDPIWriter.setDPI(x: dpi, y: dpi)
                            if attempts.isEmpty {
                                NSLog("NAGA_TEST_DPI: no HID interfaces matched — is the mouse connected?")
                            }
                            for attempt in attempts { NSLog("NAGA_TEST_DPI: %@", attempt.description) }
                        }
                    }
                    #endif
                }
        }
        .windowResizability(.contentSize)
    }
}
