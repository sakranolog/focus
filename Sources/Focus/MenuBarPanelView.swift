import SwiftUI
import AppKit

/// Compact control panel that drops down from the menu bar icon.
/// Hierarchy: tappable timer block (opens the app) → one prominent play button
/// with quiet reset/skip beside it → footer with stats-as-insights-link and mode toggles.
struct MenuBarPanelView: View {
    @Environment(FocusEngine.self) private var engine
    @Environment(\.openWindow) private var openWindow
    @State private var showSettings = false

    private var theme: PhaseTheme { PhaseTheme.theme(for: engine.phase) }

    var body: some View {
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
                footerIcon("pip.enter", help: "Floating mini-timer") {
                    engine.settings.showMini.toggle()
                }
                footerIcon("gearshape.fill", help: "Settings") {
                    showSettings.toggle()
                }
                .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                    SettingsView()
                }
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 280)
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
