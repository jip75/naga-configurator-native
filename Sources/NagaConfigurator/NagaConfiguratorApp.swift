import SwiftUI
import AppKit

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
        Self.terminateIfAnotherInstanceIsRunning()
    }

    // The dev build (.build/.../NagaConfigurator, launched by hand via Terminal/Finder
    // double-click) and the installed .app are two DIFFERENT code identities to macOS, so
    // nothing stops both from running at once. When they do, they fight over the same
    // exclusive resource — the CGEventTap that swallows/remaps key/button events — and which
    // one "wins" depends on tap insertion order, producing exactly the random "sometimes this
    // copy works, sometimes it doesn't" behavior reported across multiple sessions. Refusing to
    // launch a second copy (whichever process gets here first stays; a later launch quits
    // itself) makes that structurally impossible instead of relying on remembering not to do it.
    private static func terminateIfAnotherInstanceIsRunning() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != myPID && $0.executableURL?.lastPathComponent == "NagaConfigurator"
        }
        guard !others.isEmpty else { return }
        NSLog("NagaConfiguratorApp: another instance (pid=\(others.map { $0.processIdentifier })) is already running — quitting rather than fight it for the HID event tap")
        others.first?.activate(options: [.activateAllWindows])
        let alert = NSAlert()
        alert.messageText = "Naga Configurator is already running"
        alert.informativeText = "Only one copy can safely remap the mouse at a time — running two at once makes buttons behave randomly. This copy is quitting; the one already running stays active."
        alert.addButton(withTitle: "OK")
        alert.runModal()
        exit(0)
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
        // 621x643 content = the 621x671 window (28pt title bar) Jorivan picked 2026-09-26 as the
        // opening size — just above the 620x640 floor, so the diagram opens tight, not sprawling.
        .defaultSize(width: 621, height: 643)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .help) { ReportMenuItem() }
        }

        Window("Report a Bug or Idea", id: ReportWindow.id) {
            ReportView()
                .preferredColorScheme(appearance.colorScheme)
        }
        .windowResizability(.contentSize)
    }
}

enum ReportWindow { static let id = "report" }

private struct ReportMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Report a Bug or Idea…") { openWindow(id: ReportWindow.id) }
    }
}
