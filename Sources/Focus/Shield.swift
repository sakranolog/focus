import SwiftUI
import AppKit

struct SitePreset: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let icon: String
    let sites: [String]
    var apps: [BlockedApp] = []
}

enum SitePresets {
    static let all: [SitePreset] = [
        SitePreset(id: "social", name: "Social media",
                   subtitle: "Instagram, X, TikTok, Reddit & more",
                   icon: "person.2.fill",
                   sites: ["facebook.com", "instagram.com", "x.com", "twitter.com",
                           "tiktok.com", "reddit.com", "threads.net"]),
        SitePreset(id: "chats", name: "WhatsApp & chats",
                   subtitle: "WhatsApp app + web, Telegram, Discord",
                   icon: "bubble.left.and.bubble.right.fill",
                   sites: ["whatsapp", "telegram.org", "web.telegram.org",
                           "messenger.com", "discord.com"],
                   apps: [BlockedApp(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp"),
                          BlockedApp(bundleID: "ru.keepcoder.Telegram", name: "Telegram"),
                          BlockedApp(bundleID: "org.telegram.desktop", name: "Telegram Desktop"),
                          BlockedApp(bundleID: "com.hnc.Discord", name: "Discord")]),
        SitePreset(id: "il-news", name: "Israeli news",
                   subtitle: "ynet, N12, Mako, Walla & more",
                   icon: "newspaper.fill",
                   sites: ["ynet.co.il", "n12.co.il", "mako.co.il", "walla.co.il",
                           "haaretz.co.il", "israelhayom.co.il", "maariv.co.il",
                           "calcalist.co.il", "globes.co.il", "13tv.co.il", "kan.org.il"]),
        SitePreset(id: "us-news", name: "US & world news",
                   subtitle: "CNN, NYT, BBC, Bloomberg & more",
                   icon: "globe.americas.fill",
                   sites: ["cnn.com", "foxnews.com", "nytimes.com", "washingtonpost.com",
                           "bbc.com", "theguardian.com", "reuters.com", "apnews.com",
                           "nbcnews.com", "cnbc.com", "bloomberg.com", "politico.com"]),
        SitePreset(id: "video", name: "Video & streaming",
                   subtitle: "YouTube, Netflix, Twitch & more",
                   icon: "play.rectangle.fill",
                   sites: ["youtube.com", "netflix.com", "twitch.tv", "max.com",
                           "hulu.com", "disneyplus.com", "primevideo.com", "tv.apple.com"]),
        SitePreset(id: "shopping", name: "Shopping",
                   subtitle: "Amazon, AliExpress, Temu, KSP & more",
                   icon: "cart.fill",
                   sites: ["amazon.com", "ebay.com", "aliexpress.com", "temu.com",
                           "shein.com", "etsy.com", "walmart.com", "zap.co.il", "ksp.co.il"]),
        SitePreset(id: "sports", name: "Sports",
                   subtitle: "ESPN, Sport5, ONE, 365Scores & more",
                   icon: "figure.run",
                   sites: ["espn.com", "sport5.co.il", "one.co.il", "365scores.com",
                           "nba.com", "skysports.com", "bleacherreport.com", "goal.com"]),
        SitePreset(id: "tech", name: "Tech rabbit holes",
                   subtitle: "Hacker News, The Verge, Geektime & more",
                   icon: "terminal.fill",
                   sites: ["news.ycombinator.com", "techcrunch.com", "theverge.com",
                           "macrumors.com", "9to5mac.com", "geektime.co.il", "producthunt.com"]),
    ]
}

extension FocusEngine {
    /// Adds a preset's sites and apps to the blocklist (skipping duplicates) and arms the shield.
    func apply(_ preset: SitePreset) {
        var s = settings
        for site in preset.sites where !s.blockedSites.contains(site) {
            s.blockedSites.append(site)
        }
        for app in preset.apps where !s.blockedApps.contains(where: { $0.bundleID == app.bundleID }) {
            s.blockedApps.append(app)
        }
        s.shieldOn = true
        settings = s
        DistractionShield.shared.probeAutomation()
    }

    func isApplied(_ preset: SitePreset) -> Bool {
        preset.sites.allSatisfy { settings.blockedSites.contains($0) } &&
        preset.apps.allSatisfy { app in
            settings.blockedApps.contains(where: { $0.bundleID == app.bundleID })
        }
    }
}

/// Watches app activations — and, inside supported browsers, the active tab URL —
/// during focus sessions, dropping a gentle full-screen nudge on blocked distractions.
@MainActor
final class DistractionShield {
    static let shared = DistractionShield()
    private weak var engine: FocusEngine?
    private var overlays: [NSPanel] = []
    private var overlay: NSPanel? { overlays.first }
    private var peekUntil = Date.distantPast
    private var peekTimer: Timer?
    private var urlTimer: Timer?
    private var pollingBrowserID: String?
    private var polling = false

    /// Browsers whose active-tab URL we can read via Apple Events. Value = uses Safari dialect.
    private static let browsers: [String: Bool] = [
        "com.google.Chrome": false,
        "com.google.Chrome.canary": false,
        "com.brave.Browser": false,
        "com.microsoft.edgemac": false,
        "company.thebrowser.Browser": false, // Arc
        "com.vivaldi.Vivaldi": false,
        "com.apple.Safari": true,
    ]

    func start(engine: FocusEngine) {
        self.engine = engine
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in self?.appActivated(app) }
        }
    }

    /// Engine calls this on every state/settings change.
    func sessionStateChanged() {
        guard let engine else { return }
        if isGuarding(engine) {
            appActivated(NSWorkspace.shared.frontmostApplication)
        } else {
            dismiss()
            stopURLPolling()
        }
    }

    /// Fires a harmless tab read so the one-time macOS automation prompt appears
    /// while the user is still in Settings, not mid-session.
    func probeAutomation() {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            guard let id = $0.bundleIdentifier else { return false }
            return Self.browsers.keys.contains(id)
        }), let bundleID = app.bundleIdentifier else { return }
        runOSA(urlScript(for: bundleID)) { _ in }
    }

    private func isGuarding(_ engine: FocusEngine) -> Bool {
        engine.settings.standaloneShield ||
            (engine.settings.shieldOn && engine.runState == .running && engine.phase == .focus)
    }

    // MARK: - App shield

    private func appActivated(_ app: NSRunningApplication?) {
        guard let engine, isGuarding(engine) else {
            stopURLPolling()
            return
        }
        updateURLPolling(frontmost: app)
        guard let app, let bundleID = app.bundleIdentifier,
              bundleID != (Bundle.main.bundleIdentifier ?? ""),
              engine.settings.blockedApps.contains(where: { $0.bundleID == bundleID }),
              Date() >= peekUntil else { return }
        show(name: app.localizedName ?? "That app") { [weak self] in
            app.hide()
            self?.dismiss()
        }
    }

    // MARK: - Website shield

    private func updateURLPolling(frontmost: NSRunningApplication?) {
        guard let engine, isGuarding(engine), !engine.settings.blockedSites.isEmpty,
              let bundleID = frontmost?.bundleIdentifier,
              Self.browsers.keys.contains(bundleID) else {
            stopURLPolling()
            return
        }
        if pollingBrowserID == bundleID, urlTimer != nil { return }
        pollingBrowserID = bundleID
        urlTimer?.invalidate()
        urlTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollURL() }
        }
        pollURL()
    }

    private func stopURLPolling() {
        urlTimer?.invalidate()
        urlTimer = nil
        pollingBrowserID = nil
    }

    private func pollURL() {
        guard let engine, isGuarding(engine), overlay == nil, !polling,
              Date() >= peekUntil,
              let bundleID = pollingBrowserID else { return }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
            stopURLPolling()
            return
        }
        polling = true
        runOSA(urlScript(for: bundleID)) { [weak self] output in
            Task { @MainActor in
                self?.polling = false
                self?.handleURL(output, browserID: bundleID)
            }
        }
    }

    private func handleURL(_ urlString: String?, browserID: String) {
        guard let engine, isGuarding(engine), overlay == nil, Date() >= peekUntil,
              let urlString, !urlString.isEmpty,
              let host = URL(string: urlString)?.host?.lowercased() else { return }
        // Entries with a dot are domains (exact or subdomain match);
        // entries without a dot are keywords matched anywhere in the host
        // ("n12" catches www.n12.co.il).
        let match = engine.settings.blockedSites.first { site in
            if site.contains(".") {
                return host == site || host.hasSuffix("." + site)
            }
            return host.contains(site)
        }
        guard let site = match else { return }
        show(name: site) { [weak self] in
            self?.closeActiveTab(browserID: browserID)
            // brief grace so the next poll doesn't race the closing tab
            self?.peekUntil = Date().addingTimeInterval(3)
            self?.dismiss()
        }
    }

    private func urlScript(for bundleID: String) -> String {
        let safari = Self.browsers[bundleID] ?? false
        return safari
            ? "tell application id \"\(bundleID)\" to if (count of windows) > 0 then get URL of current tab of front window"
            : "tell application id \"\(bundleID)\" to if (count of windows) > 0 then get URL of active tab of front window"
    }

    private func closeActiveTab(browserID: String) {
        let safari = Self.browsers[browserID] ?? false
        let script = safari
            ? "tell application id \"\(browserID)\" to close current tab of front window"
            : "tell application id \"\(browserID)\" to close active tab of front window"
        runOSA(script) { _ in }
    }

    private func runOSA(_ script: String, completion: @escaping @Sendable (String?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        process.terminationHandler = { proc in
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            completion(proc.terminationStatus == 0 ? text : nil)
        }
        do { try process.run() } catch { completion(nil) }
    }

    // MARK: - Overlay

    private func show(name: String, onPrimary: @escaping () -> Void) {
        dismiss()
        guard let engine else { return }
        // Cover every connected screen, so no display stays usable behind the nudge.
        for screen in NSScreen.screens {
            let view = ShieldOverlayView(
                name: name,
                onPrimary: onPrimary,
                onPeek: { [weak self] in self?.peek() },
                onEnd: { [weak self] in
                    self?.dismiss()
                    guard let engine = self?.engine else { return }
                    if engine.runState == .running && engine.phase == .focus {
                        engine.resetTapped()
                    } else {
                        engine.settings.standaloneShield = false
                    }
                })
                .environment(engine)
            let panel = KeyablePanel(contentRect: screen.frame,
                                     styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.contentView = FirstMouseHostingView(rootView: view)
            panel.setFrame(screen.frame, display: true)
            overlays.append(panel)
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        }
    }

    func dismiss() {
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        peekTimer?.invalidate()
        peekTimer = nil
    }

    private func peek() {
        peekUntil = Date().addingTimeInterval(60)
        dismiss()
        // Websites re-nudge via polling; blocked apps need this one re-check.
        peekTimer = Timer.scheduledTimer(withTimeInterval: 65, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, let engine = self.engine, self.isGuarding(engine) else { return }
                self.appActivated(NSWorkspace.shared.frontmostApplication)
            }
        }
    }
}

struct ShieldOverlayView: View {
    @Environment(FocusEngine.self) private var engine
    let name: String
    let onPrimary: () -> Void
    let onPeek: () -> Void
    let onEnd: () -> Void

    private var theme: PhaseTheme { PhaseTheme.theme(for: .focus) }
    private var sessionActive: Bool { engine.runState == .running && engine.phase == .focus }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(Color.black.opacity(0.55))
            AuroraBackground(theme: theme)
                .opacity(0.45)
                .allowsHitTesting(false)
            VStack(spacing: 16) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(theme.glow.opacity(0.9))
                Text("DISTRACTION SHIELD")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.45))
                Text(headline)
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
                TimelineView(.periodic(from: .now, by: 0.5)) { tl in
                    Text(subtitle(at: tl.date))
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }
                HStack(spacing: 14) {
                    shieldButton("Back to focus", prominent: true, action: onPrimary)
                        .keyboardShortcut(.return, modifiers: [])
                    shieldButton("1-minute peek", action: onPeek)
                        .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(.top, 10)
                Button(sessionActive ? "End session" : "Turn off shield", action: onEnd)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 4)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var headline: String {
        guard sessionActive else { return "Not now." }
        return engine.intention.isEmpty ? "You're mid-focus." : "“\(engine.intention)”"
    }

    private func subtitle(at date: Date) -> String {
        guard sessionActive else {
            return "\(name) can wait — the shield is up."
        }
        if engine.inFlow {
            return "\(name) can wait — you're \(engine.displayTime(at: date)) into flow."
        }
        return "\(name) can wait — \(engine.displayTime(at: date)) left in this session."
    }

    private func shieldButton(_ title: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(prominent ? 1 : 0.8))
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .background(Capsule().fill(.white.opacity(prominent ? 0.16 : 0.07)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .contentShape(Capsule())
                .shadow(color: prominent ? theme.glow.opacity(0.4) : .clear, radius: 14)
        }
        .buttonStyle(.plain)
    }
}
