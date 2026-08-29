import SwiftUI
import AppKit

struct MainView: View {
    /// Snapshot renders bypass onboarding.
    var forceContent = false
    @Environment(FocusEngine.self) private var engine
    @Environment(\.openWindow) private var openWindow
    @State private var showSettings = false
    @FocusState private var intentionFocused: Bool

    private var theme: PhaseTheme { PhaseTheme.theme(for: engine.phase) }
    private var showOnboarding: Bool { !engine.settings.onboarded && !forceContent }

    var body: some View {
        ZStack {
            AuroraBackground(theme: theme)
            if showOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else {
                mainContent
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            }
        }
        .frame(width: 340, height: 560)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 1.4), value: engine.phase)
        .animation(.easeInOut(duration: 0.7), value: showOnboarding)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 10)
            TimelineView(.animation(minimumInterval: 0.1)) { tl in
                dial(at: tl.date)
            }
            .frame(width: 260, height: 260)
            cycleDots
                .padding(.top, 20)
            intentionField
                .padding(.top, 16)
            Spacer(minLength: 10)
            controls
            footer
                .padding(.top, 16)
        }
        .padding(18)
    }

    // MARK: - Pieces

    private var header: some View {
        ZStack {
            Text("FOCUS")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(5)
                .foregroundStyle(.white.opacity(0.30))
            HStack(spacing: 4) {
                Spacer()
                headerButton("chart.bar.xaxis", help: "Insights") {
                    openWindow(id: "insights")
                    NSApp.activate(ignoringOtherApps: true)
                }
                headerButton("pip.enter", help: "Floating mini-timer") {
                    engine.settings.showMini.toggle()
                }
                headerButton("gearshape.fill", help: "Settings") {
                    showSettings.toggle()
                }
                .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                    SettingsView()
                }
            }
        }
        .padding(.top, 4)
    }

    private func headerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func dial(at date: Date) -> some View {
        let timeText = engine.displayTime(at: date)
        let status = statusLabel(at: date)
        return ZStack {
            RingView(progress: engine.displayProgress(at: date), theme: theme, size: 260)
            VStack(spacing: 8) {
                Text(timeText)
                    .font(.system(size: 50, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.linear(duration: 0.3), value: timeText)
                Text(status)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(3.5)
                    .foregroundStyle(.white.opacity(0.5))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.8), value: status)
            }
        }
    }

    private func statusLabel(at date: Date) -> String {
        if engine.inFlow { return "IN FLOW" }
        if engine.runState == .running, engine.phase != .focus {
            return Int(date.timeIntervalSinceReferenceDate / 4) % 2 == 0 ? "BREATHE IN" : "BREATHE OUT"
        }
        if engine.runState == .paused { return "PAUSED" }
        return engine.phase.title.uppercased()
    }

    private var cycleDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<engine.settings.sessionsPerCycle, id: \.self) { i in
                Circle()
                    .fill(i < engine.completedInCycle ? AnyShapeStyle(theme.glow) : AnyShapeStyle(.white.opacity(0.15)))
                    .frame(width: 5, height: 5)
            }
        }
    }

    private var intentionField: some View {
        @Bindable var engine = engine
        return TextField("", text: $engine.intention,
                         prompt: Text("What's the one thing?").foregroundStyle(.white.opacity(0.28)))
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 14, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
            .tint(theme.glow)
            .focused($intentionFocused)
            .onSubmit {
                intentionFocused = false
                if engine.runState != .running { engine.start() }
            }
            .frame(width: 250)
    }

    private var controls: some View {
        HStack(spacing: 24) {
            GlassButton(symbol: "arrow.counterclockwise", size: 40) { engine.resetTapped() }
                .help("Reset")
            GlassButton(symbol: engine.runState == .running ? "pause.fill" : "play.fill",
                        size: 68, prominent: true, glow: theme.glow) { engine.toggle() }
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Start / pause (⌘↩)")
            GlassButton(symbol: "forward.end", size: 40) { engine.skipTapped() }
                .help("Skip to next phase")
        }
    }

    private var footer: some View {
        HStack {
            soundMenu
            Spacer()
            Text(engine.history.summaryLine)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
            Color.clear.frame(width: 28, height: 28)
        }
    }

    private var soundMenu: some View {
        let tracks = MusicLibrary.tracks()
        return Menu {
            Picker("Sound", selection: Binding(get: { engine.settings.soundscapeRaw },
                                               set: { engine.setSound(raw: $0) })) {
                Label("Silence", systemImage: "speaker.slash").tag("off")
                Section("Noise") {
                    ForEach([Soundscape.noise, .rain, .ocean]) { s in
                        Label(s.name, systemImage: s.symbol).tag(s.rawValue)
                    }
                }
                if !tracks.isEmpty {
                    Section("Music") {
                        ForEach(tracks) { t in
                            Label(t.name, systemImage: "music.note").tag("music:" + t.name)
                        }
                    }
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: engine.soundChoice.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Focus sound — noise or music")
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(FocusEngine.self) private var engine
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @AppStorage("settingsTab") private var tab = 0
    @State private var newSite = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Picker("", selection: $tab) {
                Text("Timer").tag(0)
                Text("Shield").tag(1)
                Text("Sound").tag(2)
                Text("General").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            switch tab {
            case 1: shieldTab
            case 2: soundTab
            case 3: generalTab
            default: timerTab
            }
        }
        .font(.system(size: 12))
        .toggleStyle(.switch)
        .controlSize(.mini)
        .padding(16)
        .frame(width: 300)
    }

    // MARK: Timer

    @ViewBuilder
    private var timerTab: some View {
        @Bindable var engine = engine
        sectionHeader("DURATIONS")
        durationRow("Focus", value: $engine.settings.focusMinutes, range: 5...120, step: 5)
        durationRow("Short break", value: $engine.settings.shortBreakMinutes, range: 1...30, step: 1)
        durationRow("Long break", value: $engine.settings.longBreakMinutes, range: 5...60, step: 5)
        durationRow("Sessions per cycle", value: $engine.settings.sessionsPerCycle, range: 2...8, step: 1, unit: "")

        Divider()
        sectionHeader("RHYTHM")
        Toggle("Auto-start breaks", isOn: $engine.settings.autoStartBreaks)
        Toggle("Auto-start next focus", isOn: $engine.settings.autoStartFocus)
        Toggle("Flow mode — extend while active", isOn: $engine.settings.flowModeOn)
            .help("If you're still typing when the timer ends, it keeps rolling until you go idle.")
        Toggle("Confirm skip/reset, offer to log", isOn: $engine.settings.confirmAbort)
            .help("Skipping or resetting mid-session asks first and can log the partial time.")
    }

    // MARK: Shield

    @ViewBuilder
    private var shieldTab: some View {
        @Bindable var engine = engine
        Toggle(isOn: $engine.settings.shieldOn) {
            Label("Distraction shield", systemImage: "shield.lefthalf.filled")
        }
        Text("During focus, blocked apps and websites get a gentle full-screen nudge.")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        if engine.settings.shieldOn {
            Divider()
            sectionHeader("APPS")
            listContainer {
                if engine.settings.blockedApps.isEmpty {
                    Text("No blocked apps yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                ForEach(engine.settings.blockedApps) { app in
                    removableRow(icon: "nosign", text: app.name) {
                        engine.settings.blockedApps.removeAll { $0.bundleID == app.bundleID }
                    }
                }
            }
            Menu("Block a running app…") {
                ForEach(candidateApps(), id: \.bundleID) { app in
                    Button(app.name) {
                        engine.settings.blockedApps.append(app)
                    }
                }
            }
            .controlSize(.small)

            Divider()
            sectionHeader("WEBSITES")
            siteRows
            HStack(spacing: 6) {
                TextField("twitter.com or n12", text: $newSite)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .onSubmit { addSite() }
                Button("Add") { addSite() }
                    .controlSize(.small)
                    .disabled(newSite.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            sectionHeader("PRESETS")
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(SitePresets.all) { preset in
                        presetRow(preset)
                    }
                }
            }
            .frame(height: 150)
            Text("Domains match subdomains; a word without a dot matches anywhere (\"n12\" blocks n12.co.il). Chrome, Safari, Brave, Edge & Arc — macOS asks once for permission to read the active tab.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var siteRows: some View {
        let sites = engine.settings.blockedSites
        if sites.count > 7 {
            ScrollView {
                siteRowsInner
            }
            .frame(height: 168)
        } else {
            siteRowsInner
        }
    }

    private var siteRowsInner: some View {
        listContainer {
            if engine.settings.blockedSites.isEmpty {
                Text("No blocked sites yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            ForEach(engine.settings.blockedSites, id: \.self) { site in
                removableRow(icon: "globe", text: site) {
                    engine.settings.blockedSites.removeAll { $0 == site }
                }
            }
        }
    }

    private func addSite() {
        var site = newSite.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !site.isEmpty else { return }
        if let url = URL(string: site.contains("://") ? site : "https://" + site),
           let host = url.host {
            site = host
        }
        if site.hasPrefix("www.") { site = String(site.dropFirst(4)) }
        if !site.isEmpty, !engine.settings.blockedSites.contains(site) {
            engine.settings.blockedSites.append(site)
        }
        newSite = ""
        DistractionShield.shared.probeAutomation()
    }

    private func presetRow(_ preset: SitePreset) -> some View {
        let applied = engine.isApplied(preset)
        return Button {
            engine.apply(preset)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: preset.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 0) {
                    Text(preset.name)
                        .font(.system(size: 11, weight: .medium))
                    Text(preset.subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: applied ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(applied ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(applied ? 0.5 : 0.3)))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(applied)
        .help(preset.sites.joined(separator: ", "))
    }

    private func candidateApps() -> [BlockedApp] {
        let blocked = Set(engine.settings.blockedApps.map(\.bundleID))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> BlockedApp? in
                guard let id = app.bundleIdentifier,
                      let name = app.localizedName,
                      id != Bundle.main.bundleIdentifier,
                      !blocked.contains(id) else { return nil }
                return BlockedApp(bundleID: id, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Sound

    @ViewBuilder
    private var soundTab: some View {
        @Bindable var engine = engine
        sectionHeader("FOCUS SOUND")
        Picker("", selection: Binding(get: { engine.settings.soundscapeRaw },
                                      set: { engine.setSound(raw: $0) })) {
            Text("Silence").tag("off")
            Section("Noise") {
                ForEach([Soundscape.noise, .rain, .ocean]) { s in
                    Text(s.name).tag(s.rawValue)
                }
            }
            Section("Music") {
                ForEach(MusicLibrary.tracks()) { t in
                    Text(t.name).tag("music:" + t.name)
                }
            }
        }
        .labelsHidden()
        .controlSize(.small)
        HStack(spacing: 8) {
            Image(systemName: "speaker.wave.1").foregroundStyle(.secondary)
            Slider(value: $engine.settings.soundscapeVolume, in: 0...1)
            Image(systemName: "speaker.wave.3").foregroundStyle(.secondary)
        }
        Text("Plays during focus only. Add your own tracks to ~/Library/Application Support/Focus/Music.")
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)

        Divider()
        sectionHeader("CHIME")
        HStack {
            Toggle("Chime when phases end", isOn: $engine.settings.chimeOn)
            Spacer()
            Button("Test") { engine.sound.chime(.sessionEnd) }
                .controlSize(.small)
        }
    }

    // MARK: General

    @ViewBuilder
    private var generalTab: some View {
        @Bindable var engine = engine
        sectionHeader("STARTUP")
        Toggle("Launch at login", isOn: $engine.settings.launchAtLogin)

        Divider()
        sectionHeader("APPEARANCE")
        Toggle("Hide Dock icon", isOn: $engine.settings.hideDockIcon)
        Toggle("Floating mini-timer", isOn: $engine.settings.showMini)

        Divider()
        Button {
            dismiss()
            engine.settings.onboarded = false
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label("Replay onboarding", systemImage: "sparkles")
        }
        .controlSize(.small)

        Text("Focus 1.0 — one thing at a time.")
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
    }

    // MARK: Shared bits

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(1.5)
            .foregroundStyle(.secondary)
    }

    private func listContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.35)))
    }

    private func removableRow(icon: String, text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func durationRow(_ label: String, value: Binding<Int>,
                             range: ClosedRange<Int>, step: Int, unit: String = " min") -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value.wrappedValue)\(unit)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
        }
    }
}
