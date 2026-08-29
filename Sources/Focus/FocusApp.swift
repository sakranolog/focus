import SwiftUI
import AppKit
import UserNotifications

@main
struct FocusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Headless renders for development:
        //   Focus --snapshot out.png [break] [running] | insights | shield
        if let idx = CommandLine.arguments.firstIndex(of: "--snapshot"),
           CommandLine.arguments.count > idx + 1 {
            let path = CommandLine.arguments[idx + 1]
            let args = CommandLine.arguments
            let engine = FocusEngine.shared
            if args.contains("insights") {
                engine.history.seedDemo()
                Self.writeSnapshot(InsightsView(snapshotMode: true).environment(engine), to: path)
            } else if args.contains("shield") {
                engine.intention = "Ship the focus app"
                engine.start()
                engine.debugFastForward(engine.total * 0.4)
                Self.writeSnapshot(ShieldOverlayView(name: "twitter.com",
                                                     primaryLabel: "Close the tab",
                                                     onPrimary: {}, onPeek: {}, onEnd: {})
                    .environment(engine)
                    .frame(width: 900, height: 560), to: path)
            } else if let arg = args.first(where: { $0.hasPrefix("onboarding") }) {
                let n = Int(arg.dropFirst("onboarding".count)) ?? 0
                Self.writeSnapshot(
                    ZStack {
                        AuroraBackground(theme: PhaseTheme.theme(for: .focus))
                        OnboardingView(startStep: n).environment(engine)
                    }
                    .frame(width: 340, height: 560)
                    .preferredColorScheme(.dark), to: path)
            } else {
                if args.contains("break") { engine.phase = .shortBreak }
                if args.contains("running") {
                    engine.intention = "Ship the focus app"
                    engine.start()
                    engine.debugFastForward(engine.total * 0.38)
                }
                Self.writeSnapshot(MainView(forceContent: true).environment(engine), to: path)
            }
            exit(0)
        }
    }

    @MainActor
    private static func writeSnapshot<V: View>(_ view: V, to path: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let img = renderer.nsImage,
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    var body: some Scene {
        Window("Focus", id: "main") {
            MainView()
                .environment(FocusEngine.shared)
                .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Insights", id: "insights") {
            InsightsView()
                .environment(FocusEngine.shared)
                .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarPanelView()
                .environment(FocusEngine.shared)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

/// Live menu-bar label: icon + ticking countdown while a session runs.
struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let engine = FocusEngine.shared
        HStack(spacing: 4) {
            Image(systemName: engine.runState == .running ? "circle.circle.fill" : "circle.circle")
            if !engine.menuTitle.isEmpty {
                Text(engine.menuTitle).monospacedDigit()
            }
        }
        .onAppear {
            AppDelegate.reopenMainWindow = { openWindow(id: "main") }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static var reopenMainWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DistractionShield.shared.start(engine: FocusEngine.shared)
        FocusEngine.shared.applySettings()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
        NSApp.activate(ignoringOtherApps: true)
        // If onboarding hasn't run yet, make sure the main window actually shows —
        // state restoration may have left it closed (e.g. Dock icon hidden, window closed).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Self.presentMainWindowIfNeeded()
        }
    }

    static func presentMainWindowIfNeeded() {
        guard !FocusEngine.shared.settings.onboarded else { return }
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            Self.reopenMainWindow?()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // keep living in the menu bar
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Self.reopenMainWindow?() }
        return true
    }

    // Show banners even while the app is frontmost.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}

/// Grabs the hosting NSWindow to allow dragging the chromeless window anywhere.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            window.backgroundColor = .black
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
