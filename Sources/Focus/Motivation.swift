import SwiftUI
import AppKit

/// Motivational aura nudges: a click-through, glowing message that drifts up
/// from the bottom of the active screen during focus sessions.
@MainActor
final class MotivationController {
    static let shared = MotivationController()
    private var panel: NSPanel?
    private var counter = 0

    private static let main = [
        "Keep pushing.",
        "Deep in it. Stay there.",
        "One thing. This thing.",
        "The resistance is lying.",
        "Don't break the spell.",
        "Every minute here compounds.",
        "Shallow can wait.",
        "This is the work that matters.",
        "You chose this. Own it.",
        "Distraction is a decision. So is this.",
        "Quiet mind, loud results.",
        "Future you says thanks.",
        "Still here? That's the whole secret.",
        "Depth beats speed.",
        "Protect the streak.",
        "Nobody drifts to the top.",
    ]
    private static let closing = [
        "Almost there — finish strong.",
        "Last stretch. Land it.",
        "Close it out like you mean it.",
        "The ring is almost full.",
    ]
    private static let flow = [
        "You're in flow — ride it.",
        "This is the good stuff. Stay.",
        "Flow found you. Don't look up.",
        "Bonus minutes. Make them count.",
    ]

    func show(engine: FocusEngine) {
        dismiss()
        counter += 1
        let now = Date()

        let message: String
        if engine.inFlow {
            message = Self.flow[counter % Self.flow.count]
        } else if engine.progress(at: now) > 0.8 {
            message = Self.closing[counter % Self.closing.count]
        } else if counter % 3 == 0, !engine.intention.isEmpty {
            message = "“\(engine.intention)” — that's all there is right now."
        } else {
            message = Self.main[counter % Self.main.count]
        }
        let caption = engine.inFlow
            ? "\(engine.displayTime(at: now)) in flow"
            : "\(FocusEngine.format(engine.remaining(at: now))) left"

        guard let screen = screenWithMouse() else { return }
        let width: CGFloat = 660
        let height: CGFloat = 210
        let frame = NSRect(x: screen.visibleFrame.midX - width / 2,
                           y: screen.visibleFrame.minY + 100,
                           width: width, height: height)
        let p = NSPanel(contentRect: frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.contentView = NSHostingView(rootView: MotivationToastView(message: message,
                                                                    caption: caption,
                                                                    theme: PhaseTheme.theme(for: .focus)))
        p.setFrame(frame, display: true)
        p.orderFrontRegardless()
        panel = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.5) { [weak self] in
            guard let self, self.panel === p else { return }
            self.dismiss()
        }
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func screenWithMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
    }
}

struct MotivationToastView: View {
    let message: String
    let caption: String
    let theme: PhaseTheme
    var startVisible = false
    @State private var visible: Bool

    init(message: String, caption: String, theme: PhaseTheme, startVisible: Bool = false) {
        self.message = message
        self.caption = caption
        self.theme = theme
        self.startVisible = startVisible
        _visible = State(initialValue: startVisible)
    }

    var body: some View {
        ZStack {
            // dark scrim keeps the text legible over bright windows
            Ellipse()
                .fill(RadialGradient(colors: [.black.opacity(0.45), .clear],
                                     center: .center, startRadius: 0, endRadius: 310))
                .frame(width: 640, height: 210)
                .blur(radius: 24)
            // the aura
            Ellipse()
                .fill(RadialGradient(colors: [theme.glow.opacity(0.5),
                                              theme.blobs[1].opacity(0.22),
                                              .clear],
                                     center: .center, startRadius: 0, endRadius: 300))
                .frame(width: 620, height: 190)
                .blur(radius: 28)
            VStack(spacing: 9) {
                Text(message)
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: theme.glow.opacity(0.85), radius: 14)
                    .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 600)
                Text(caption.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.75))
                    .shadow(color: .black.opacity(0.6), radius: 2)
            }
            .offset(y: visible ? 0 : 16)
            .blur(radius: visible ? 0 : 6)
        }
        .opacity(visible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !startVisible else { return }
            withAnimation(.easeOut(duration: 0.7)) { visible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                withAnimation(.easeIn(duration: 1.1)) { visible = false }
            }
        }
    }
}
