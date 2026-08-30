import SwiftUI
import AppKit

/// Compact control panel that drops down from the menu bar icon.
/// Hierarchy: tappable timer block (opens the app) → one prominent play button
/// with quiet reset/skip beside it → footer with stats-as-insights-link and mode toggles.
struct MenuBarPanelView: View {
    @Environment(FocusEngine.self) private var engine
    @Environment(\.openWindow) private var openWindow
    @State private var showSettings = false
    @State private var confirmQuit = false

    private var theme: PhaseTheme { PhaseTheme.theme(for: engine.phase) }

    var body: some View {
        Group {
            if confirmQuit {
                quitConfirm
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                panelContent
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.3), value: confirmQuit)
        .onDisappear { confirmQuit = false }
    }

    private var panelContent: some View {
        VStack(spacing: 12) {
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                TimelineView(.periodic(from: .now, by: 0.5)) { tl in
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().stroke(.quaternary, lineWidth: 5)
                            Circle()
                                .trim(from: 0, to: max(engine.displayProgress(at: tl.date), 0.003))
                                .stroke(AngularGradient(colors: theme.ring, center: .center,
                                                        startAngle: .degrees(-90), endAngle: .degrees(270)),
                                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 46, height: 46)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(engine.displayTime(at: tl.date))
                                .font(.system(size: 24, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .help("Open Focus")

            HStack(spacing: 18) {
                transportButton("arrow.counterclockwise") { engine.resetTapped() }
                    .help("Reset")
                playButton
                transportButton("forward.end.fill") { engine.skipTapped() }
                    .help("Skip to next phase")
            }
            .frame(maxWidth: .infinity)

            Divider()

            HStack(spacing: 12) {
                Button {
                    openWindow(id: "insights")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 9, weight: .medium))
                        Text(engine.history.summaryLine)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Insights")

                Spacer()

                footerIcon(engine.settings.standaloneShield ? "shield.fill" : "shield",
                           tinted: engine.settings.standaloneShield,
                           help: "Shield mode — block distractions anytime") {
                    engine.settings.standaloneShield.toggle()
                }
                footerIcon("gearshape.fill", help: "Settings") {
                    showSettings.toggle()
                }
                .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                    SettingsView()
                }
                footerIcon("power", help: "Quit Focus") {
                    confirmQuit = true
                }
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private var quitConfirm: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(theme.glow.opacity(0.14))
                    .frame(width: 54, height: 54)
                Image(systemName: "power")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(theme.glow)
            }
            .padding(.top, 8)
            VStack(spacing: 4) {
                Text("Quit Focus?")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(quitCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button {
                    confirmQuit = false
                } label: {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.quaternary.opacity(0.6)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(theme.glow))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.bottom, 4)
        }
        .padding(14)
        .frame(width: 280)
    }

    private var quitCaption: String {
        if engine.phase == .focus, engine.runState == .running || engine.runState == .paused {
            let elapsed = engine.inFlow
                ? engine.total + engine.overtime(at: Date())
                : engine.total - engine.remaining(at: Date())
            let minutes = Int(elapsed / 60)
            if minutes >= 1 {
                return "You're mid-focus — your \(minutes) focused min will be logged before quitting."
            }
        }
        return "Timer, shield and sounds stop until you open it again."
    }

    private var subtitle: String {
        if engine.inFlow { return "In flow ⚡" }
        if !engine.intention.isEmpty && engine.phase == .focus {
            return engine.intention
        }
        return engine.phase.title
    }

    private var playButton: some View {
        Button { engine.toggle() } label: {
            ZStack {
                Circle().fill(theme.glow)
                Image(systemName: engine.runState == .running ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            .shadow(color: theme.glow.opacity(0.45), radius: 8, y: 2)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Start / pause")
    }

    private func transportButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(.quaternary.opacity(0.6))
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 30, height: 30)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func footerIcon(_ symbol: String, tinted: Bool = false, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tinted ? AnyShapeStyle(theme.glow) : AnyShapeStyle(.secondary))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
