import SwiftUI

struct PhaseTheme {
    let backdrop: Color
    let blobs: [Color]
    let ring: [Color]
    let glow: Color

    static func theme(for phase: Phase) -> PhaseTheme {
        switch phase {
        case .focus:
            return PhaseTheme(
                backdrop: Color(red: 0.055, green: 0.045, blue: 0.10),
                blobs: [Color(red: 0.95, green: 0.45, blue: 0.18),
                        Color(red: 0.75, green: 0.20, blue: 0.45),
                        Color(red: 0.30, green: 0.18, blue: 0.65)],
                ring: [Color(red: 1.00, green: 0.62, blue: 0.26),
                       Color(red: 1.00, green: 0.35, blue: 0.42),
                       Color(red: 0.92, green: 0.30, blue: 0.65),
                       Color(red: 1.00, green: 0.62, blue: 0.26)],
                glow: Color(red: 1.00, green: 0.52, blue: 0.30))
        case .shortBreak:
            return PhaseTheme(
                backdrop: Color(red: 0.03, green: 0.07, blue: 0.09),
                blobs: [Color(red: 0.15, green: 0.65, blue: 0.55),
                        Color(red: 0.10, green: 0.45, blue: 0.65),
                        Color(red: 0.20, green: 0.30, blue: 0.60)],
                ring: [Color(red: 0.35, green: 0.95, blue: 0.75),
                       Color(red: 0.25, green: 0.75, blue: 0.95),
                       Color(red: 0.45, green: 0.85, blue: 0.95),
                       Color(red: 0.35, green: 0.95, blue: 0.75)],
                glow: Color(red: 0.35, green: 0.90, blue: 0.75))
        case .longBreak:
            return PhaseTheme(
                backdrop: Color(red: 0.05, green: 0.045, blue: 0.11),
                blobs: [Color(red: 0.45, green: 0.30, blue: 0.85),
                        Color(red: 0.25, green: 0.35, blue: 0.85),
                        Color(red: 0.60, green: 0.25, blue: 0.70)],
                ring: [Color(red: 0.70, green: 0.55, blue: 1.00),
                       Color(red: 0.45, green: 0.65, blue: 1.00),
                       Color(red: 0.85, green: 0.50, blue: 0.95),
                       Color(red: 0.70, green: 0.55, blue: 1.00)],
                glow: Color(red: 0.62, green: 0.52, blue: 1.00))
        }
    }
}

/// Slowly drifting blurred color fields — the app's living backdrop.
struct AuroraBackground: View {
    let theme: PhaseTheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 14.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                theme.backdrop
                Group {
                    blob(theme.blobs[0], 320)
                        .offset(x: 100 * CGFloat(sin(t * 0.11)),
                                y: -150 + 60 * CGFloat(cos(t * 0.09)))
                    blob(theme.blobs[1], 280)
                        .offset(x: -110 + 70 * CGFloat(cos(t * 0.07 + 1.3)),
                                y: 150 + 80 * CGFloat(sin(t * 0.05)))
                    blob(theme.blobs[2], 260)
                        .offset(x: 120 * CGFloat(cos(t * 0.05 + 3.1)),
                                y: 250 + 50 * CGFloat(sin(t * 0.08 + 2.0)))
                }
                .blur(radius: 46)
                .opacity(0.55)
            }
            .ignoresSafeArea()
        }
    }

    private func blob(_ color: Color, _ size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color, color.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
    }
}

struct RingView: View {
    let progress: Double
    let theme: PhaseTheme
    var size: CGFloat = 260
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: max(progress, 0.003))
                .stroke(AngularGradient(colors: theme.ring, center: .center,
                                        startAngle: .degrees(-90), endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: theme.glow.opacity(0.7), radius: 12)
                .shadow(color: theme.glow.opacity(0.35), radius: 28)
            Circle()
                .fill(.white)
                .frame(width: 7, height: 7)
                .shadow(color: theme.glow, radius: 6)
                .offset(y: -size / 2)
                .rotationEffect(.degrees(progress * 360))
                .opacity(progress > 0.004 ? 1 : 0)
        }
        .frame(width: size, height: size)
    }
}

struct GlassButton: View {
    let symbol: String
    var size: CGFloat = 40
    var prominent = false
    var glow: Color = .clear
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if prominent {
                    Circle().fill(
                        LinearGradient(colors: [glow, glow.opacity(0.75)],
                                       startPoint: .top, endPoint: .bottom))
                    Circle().strokeBorder(.white.opacity(hovering ? 0.5 : 0.25), lineWidth: 1)
                } else {
                    Circle().fill(.white.opacity(0.06))
                    Circle().strokeBorder(.white.opacity(hovering ? 0.35 : 0.14), lineWidth: 1)
                }
                Image(systemName: symbol)
                    .font(.system(size: size * 0.30, weight: .semibold))
                    .foregroundStyle(prominent ? .white : .white.opacity(0.85))
            }
            .frame(width: size, height: size)
            .shadow(color: glow.opacity(prominent ? 0.55 : 0), radius: hovering ? 22 : 14, y: 2)
            .scaleEffect(hovering ? 1.05 : 1)
            .animation(.spring(duration: 0.25), value: hovering)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
