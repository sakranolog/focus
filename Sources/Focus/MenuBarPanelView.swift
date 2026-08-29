import SwiftUI
import AppKit

/// Compact control panel that drops down from the menu bar icon.
struct MenuBarPanelView: View {
    @Environment(FocusEngine.self) private var engine
    @Environment(\.openWindow) private var openWindow
    @State private var showSettings = false

    private var theme: PhaseTheme { PhaseTheme.theme(for: engine.phase) }

    var body: some View {
        VStack(spacing: 12) {
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
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }

            HStack(spacing: 8) {
                smallControl(engine.runState == .running ? "pause.fill" : "play.fill") { engine.toggle() }
                smallControl("forward.end.fill") { engine.skipTapped() }
                smallControl("arrow.counterclockwise") { engine.resetTapped() }
                Spacer()
                smallControl("chart.bar.xaxis") {
                    openWindow(id: "insights")
                    NSApp.activate(ignoringOtherApps: true)
                }
                smallControl("pip.enter") { engine.settings.showMini.toggle() }
                smallControl("macwindow") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }

            Divider()

            HStack {
                Text(engine.history.summaryLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
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

    private func smallControl(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 32, height: 26)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}
