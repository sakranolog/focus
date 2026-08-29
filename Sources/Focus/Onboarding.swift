import SwiftUI

/// Five-step first-run walkthrough, shown inside the main window over the aurora.
struct OnboardingView: View {
    @Environment(FocusEngine.self) private var engine
    @State private var step: Int

    private let steps = 5
    private var glow: Color { PhaseTheme.theme(for: .focus).glow }

    init(startStep: Int = 0) {
        _step = State(initialValue: startStep)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if step < steps - 1 {
                    Button("Skip") { finish() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .frame(height: 20)

            Spacer()
            Group {
                switch step {
                case 0: welcome
                case 1: ringStep
                case 2: featuresStep
                case 3: presetsStep
                default: readyStep
                }
            }
            .id(step)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            Spacer()

            dots
                .padding(.bottom, 18)
            continueButton
        }
        .padding(22)
        .animation(.spring(duration: 0.45), value: step)
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 24) {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                ZStack {
                    RingView(progress: 0.55 + 0.3 * sin(t * 0.6),
                             theme: PhaseTheme.theme(for: .focus),
                             size: 150, lineWidth: 8)
                    Text("25:00")
                        .font(.system(size: 26, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 170, height: 170)
            copyBlock("Welcome to Focus",
                      "One thing at a time. Work in glowing sprints, rest on purpose, and watch your days add up.")
        }
    }

    private var ringStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Text("What's the one thing?")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                    Image(systemName: "return")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(glow)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Capsule().fill(.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
                Image(systemName: "arrow.down")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
                HStack(spacing: 10) {
                    iconBadge("play.fill")
                    iconBadge("cup.and.saucer.fill")
                    iconBadge("wind")
                }
            }
            copyBlock("Name it, then press ⏎",
                      "Type your intention and hit Return — the session starts. When the ring completes, a warm chime leads you into a breathing break.")
        }
    }

    private var featuresStep: some View {
        VStack(spacing: 22) {
            Text("It works with you")
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 14) {
                featureRow("bolt.fill", "Flow mode",
                           "Still typing at 0:00? The timer keeps rolling until you come up for air.")
                featureRow("shield.lefthalf.filled", "Distraction shield",
                           "Blocked apps and websites get a gentle nudge — with your intention on it.")
                featureRow("chart.bar.xaxis", "Insights",
                           "Heatmaps, golden hours and streaks build up as you focus.")
            }
            Text("Everything is tunable via the ⚙ — here or in the menu bar panel.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
    }

    private var presetsStep: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(glow.opacity(0.15))
                    .frame(width: 66, height: 66)
                    .blur(radius: 8)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(glow)
            }
            copyBlock("Block the noise now",
                      "One click arms the shield. Scroll for more — edit anytime in Settings → Shield.")
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(SitePresets.all) { preset in
                        presetRow(preset)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
            }
            .frame(width: 296, height: 208)
        }
    }

    private var readyStep: some View {
        VStack(spacing: 22) {
            Text("You're set")
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 14) {
                featureRow("menubar.rectangle", "Always in your menu bar",
                           "A live countdown up top — the dropdown has full controls.")
                featureRow("pip.enter", "Floating mini-timer",
                           "A tiny glass pill that stays on top of every app and Space.")
                featureRow("music.note", "Sound to sink into",
                           "Trance, techno, lofi and ambient loops — or rain and deep noise.")
            }
            Text("25 minutes. One thing. Let's go.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    // MARK: - Bits

    private func copyBlock(_ title: String, _ text: String) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text(text)
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 270)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func iconBadge(_ symbol: String) -> some View {
        ZStack {
            Circle().fill(.white.opacity(0.07))
            Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: 40, height: 40)
    }

    private func featureRow(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(.white.opacity(0.07))
                Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(glow)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(text)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 280, alignment: .leading)
    }

    private func presetRow(_ preset: SitePreset) -> some View {
        let added = engine.isApplied(preset)
        return Button {
            engine.apply(preset)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(.white.opacity(0.07))
                    Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    Image(systemName: preset.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(added ? AnyShapeStyle(glow) : AnyShapeStyle(.white.opacity(0.7)))
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.name)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(added ? "Added — shield is on" : preset.subtitle)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(added ? AnyShapeStyle(glow) : AnyShapeStyle(.white.opacity(0.5)))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(added ? 0.10 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 11)
                .strokeBorder(added ? glow.opacity(0.5) : .white.opacity(0.12), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .disabled(added)
        .animation(.easeOut(duration: 0.25), value: added)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<steps, id: \.self) { i in
                Capsule()
                    .fill(i == step ? AnyShapeStyle(glow) : AnyShapeStyle(.white.opacity(0.2)))
                    .frame(width: i == step ? 18 : 6, height: 6)
            }
        }
    }

    private var continueButton: some View {
        Button {
            if step < steps - 1 { step += 1 } else { finish() }
        } label: {
            Text(step == steps - 1 ? "Start focusing" : "Continue")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(.white.opacity(0.14)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                .shadow(color: glow.opacity(0.35), radius: 16)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: [])
    }

    private func finish() {
        engine.settings.onboarded = true
    }
}
