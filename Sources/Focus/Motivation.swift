import SwiftUI
import AppKit

/// Motivational aura nudges: a glowing message with drifting ember particles
/// that rises from the bottom of the active screen during focus sessions.
/// Click anywhere on it to dismiss early.
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

        let custom = engine.settings.customMotivations
        let message: String
        if !custom.isEmpty && engine.settings.customMotivationsOnly {
            message = custom[counter % custom.count]
        } else if engine.inFlow {
            message = Self.flow[counter % Self.flow.count]
        } else if engine.progress(at: now) > 0.8 {
            message = Self.closing[counter % Self.closing.count]
        } else if counter % 3 == 0, !engine.intention.isEmpty {
            message = "“\(engine.intention)” — that's all there is right now."
        } else {
            let pool = Self.main + custom
            message = pool[counter % pool.count]
        }
        let caption = engine.inFlow
            ? "\(engine.displayTime(at: now)) in flow"
            : "\(FocusEngine.format(engine.remaining(at: now))) left"

        guard let screen = screenWithMouse() else { return }
        // Panel is much larger than the visible glow so blurred gradients
        // fade to nothing well inside the bounds — no clipped edges.
        let width: CGFloat = 940
        let height: CGFloat = 400
        let frame = NSRect(x: screen.visibleFrame.midX - width / 2,
                           y: screen.visibleFrame.minY + 20,
                           width: width, height: height)
        let p = NSPanel(contentRect: frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = false
        p.contentView = NSHostingView(rootView: MotivationToastView(
            message: message,
            caption: caption,
            theme: PhaseTheme.theme(for: .focus),
            onDismiss: { [weak self, weak p] in
                guard let self, let p, self.panel === p else { return }
                self.dismiss()
            }))
        p.setFrame(frame, display: true)
        p.orderFrontRegardless()
        panel = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
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
    var onDismiss: () -> Void = {}
    @State private var visible: Bool
    @State private var dismissed = false

    init(message: String, caption: String, theme: PhaseTheme,
         startVisible: Bool = false, onDismiss: @escaping () -> Void = {}) {
        self.message = message
        self.caption = caption
        self.theme = theme
        self.startVisible = startVisible
        self.onDismiss = onDismiss
        _visible = State(initialValue: startVisible)
    }

    var body: some View {
        ZStack {
            // dark scrim keeps the text legible over bright windows
            Ellipse()
                .fill(RadialGradient(colors: [.black.opacity(0.45), .clear],
                                     center: .center, startRadius: 0, endRadius: 320))
                .frame(width: 660, height: 230)
                .blur(radius: 26)
            // the aura
            Ellipse()
                .fill(RadialGradient(colors: [theme.glow.opacity(0.5),
                                              theme.blobs[1].opacity(0.22),
                                              .clear],
                                     center: .center, startRadius: 0, endRadius: 300))
                .frame(width: 620, height: 200)
                .blur(radius: 28)
            particles
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
        .contentShape(Rectangle())
        .onTapGesture { tapDismiss() }
        .onAppear {
            guard !startVisible else { return }
            withAnimation(.easeOut(duration: 0.7)) { visible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.2) {
                guard !dismissed else { return }
                withAnimation(.easeIn(duration: 1.2)) { visible = false }
            }
        }
    }

    /// Ember particles drifting up out of the glow.
    private var particles: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let centerX = size.width / 2
                let baseY = size.height * 0.60
                for i in 0..<30 {
                    let fi = Double(i)
                    let speed = 10 + (fi * 7.3).truncatingRemainder(dividingBy: 16)
                    let phase = fi * 1.7
                    let spread = 60 + (fi * 37).truncatingRemainder(dividingBy: 240)
                    let x = centerX + sin(fi * 2.4) * spread + sin(t * 0.6 + phase) * 9
                    let travel = (t * speed + fi * 47).truncatingRemainder(dividingBy: 150)
                    let y = baseY - travel + sin(t * 0.9 + phase) * 5
                    let fade = (1 - travel / 150) * (min(1, travel / 18))
                    let radius = 1.2 + (fi * 3.1).truncatingRemainder(dividingBy: 2.4)
                    let color: Color = i % 4 == 0
                        ? .white
                        : (i % 2 == 0 ? theme.glow : theme.blobs[1])
                    ctx.opacity = fade * 0.85
                    ctx.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                                    width: radius * 2, height: radius * 2)),
                             with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func tapDismiss() {
        guard !dismissed else { return }
        dismissed = true
        withAnimation(.easeIn(duration: 0.22)) { visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onDismiss() }
    }
}
