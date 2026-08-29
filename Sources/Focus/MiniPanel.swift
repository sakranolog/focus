import SwiftUI
import AppKit

/// The tiny always-on-top floating timer ("something small on top").
@MainActor
final class MiniPanelController {
    static let shared = MiniPanelController()
    private var panel: NSPanel?

    func setVisible(_ visible: Bool, engine: FocusEngine) {
        if visible { show(engine: engine) } else { panel?.orderOut(nil) }
    }

    private func show(engine: FocusEngine) {
        if panel == nil {
            let hosting = FirstMouseHostingView(rootView: MiniView().environment(engine))
            let p = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 210, height: 58),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.isMovableByWindowBackground = true
            p.hidesOnDeactivate = false
            p.contentView = hosting
            _ = p.setFrameAutosaveName("MiniTimerPanel")
            if p.frame.origin == .zero, let screen = NSScreen.main {
                let f = screen.visibleFrame
                p.setFrameOrigin(NSPoint(x: f.maxX - 230, y: f.maxY - 78))
            }
            panel = p
        }
        panel?.orderFrontRegardless()
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct MiniView: View {
    @Environment(FocusEngine.self) private var engine
    @State private var hovering = false

    private var theme: PhaseTheme { PhaseTheme.theme(for: engine.phase) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { tl in
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: max(engine.displayProgress(at: tl.date), 0.003))
                        .stroke(AngularGradient(colors: theme.ring, center: .center,
                                                startAngle: .degrees(-90), endAngle: .degrees(270)),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: engine.inFlow ? "bolt.fill" : (engine.phase == .focus ? "scope" : "cup.and.saucer.fill"))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(engine.displayTime(at: tl.date))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(engine.inFlow ? "In flow ⚡" : (engine.intention.isEmpty ? engine.phase.title : engine.intention))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if hovering {
                    HStack(spacing: 6) {
                        miniButton(engine.runState == .running ? "pause.fill" : "play.fill") {
                            engine.toggle()
                        }
                        miniButton("xmark") {
                            engine.settings.showMini = false
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .frame(width: 210, height: 58)
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(LinearGradient(colors: [theme.glow.opacity(0.22), .clear],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                    Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.18), value: hovering)
    }

    private func miniButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 22, height: 22)
                .background(Circle().fill(.white.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
