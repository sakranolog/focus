import SwiftUI
import Charts

struct InsightsView: View {
    /// ImageRenderer can't rasterize ScrollView; dev snapshots render the flat stack.
    var snapshotMode = false
    @Environment(FocusEngine.self) private var engine

    private var theme: PhaseTheme { PhaseTheme.theme(for: .longBreak) }
    private var glow: Color { PhaseTheme.theme(for: .focus).glow }

    var body: some View {
        ZStack {
            AuroraBackground(theme: theme)
            if snapshotMode {
                content.padding(24)
            } else {
                ScrollView {
                    content.padding(24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(width: 520, height: snapshotMode ? nil : 660)
        .preferredColorScheme(.dark)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if engine.history.totalSessions == 0 {
                card("YOUR STATS") {
                    Text("Complete your first focus session and this fills with heatmaps, golden hours, and streaks.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            } else {
                heatmapCard
                hoursCard
                intentionsCard
                Text("\(engine.history.totalSessions) sessions all-time")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        let h = engine.history
        let thisWeek = h.weekMinutes(offset: 0)
        let lastWeek = h.weekMinutes(offset: -1)
        let flow = h.flowMinutes(weekOffset: 0)
        return VStack(alignment: .leading, spacing: 6) {
            Text("INSIGHTS")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(5)
                .foregroundStyle(.white.opacity(0.35))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(HistoryStore.hm(thisWeek))
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                Text("this week")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                if lastWeek > 0 {
                    let delta = Int((Double(thisWeek - lastWeek) / Double(lastWeek)) * 100)
                    Text("\(delta >= 0 ? "▲" : "▼") \(abs(delta))% vs last week")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(delta >= 0
                            ? Color(red: 0.45, green: 0.9, blue: 0.65)
                            : .white.opacity(0.45))
                }
            }
            if flow > 0 {
                Text("⚡ \(HistoryStore.hm(flow)) earned in flow this week")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var heatmapCard: some View {
        card("LAST 16 WEEKS") {
            let cols = engine.history.heatmap(weeks: 16)
            HStack(alignment: .top, spacing: 3) {
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { r in
                        Text(["M", "", "W", "", "F", "", "S"][r])
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                            .frame(width: 10, height: 13)
                    }
                }
                ForEach(Array(cols.enumerated()), id: \.offset) { _, col in
                    VStack(spacing: 3) {
                        ForEach(Array(col.enumerated()), id: \.offset) { _, cell in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(cellColor(cell))
                                .frame(width: 13, height: 13)
                        }
                    }
                }
            }
            HStack {
                Text("Longest streak: \(engine.history.longestStreak) days")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                HStack(spacing: 3) {
                    Text("less")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.35))
                    ForEach([0, 30, 60, 120], id: \.self) { m in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(cellColor(m))
                            .frame(width: 9, height: 9)
                    }
                    Text("more")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
    }

    private func cellColor(_ minutes: Int?) -> Color {
        guard let m = minutes else { return .clear }
        if m == 0 { return .white.opacity(0.06) }
        return glow.opacity(0.25 + 0.75 * min(1, Double(m) / 120))
    }

    private var hoursCard: some View {
        card("GOLDEN HOURS") {
            let hist = engine.history.hourHistogram
            Chart(Array(hist.enumerated()), id: \.offset) { item in
                BarMark(x: .value("Hour", item.offset),
                        y: .value("Minutes", item.element),
                        width: .fixed(11))
                    .cornerRadius(2)
                    .foregroundStyle(LinearGradient(colors: [glow.opacity(0.9),
                                                             Color(red: 1, green: 0.35, blue: 0.42)],
                                                    startPoint: .bottom, endPoint: .top))
            }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisValueLabel {
                        if let h = value.as(Int.self) {
                            Text("\(h):00")
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 110)
            if let peak = hist.enumerated().max(by: { $0.element < $1.element }), peak.element > 0 {
                Text("You focus best around \(peak.offset):00")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private var intentionsCard: some View {
        card("TOP INTENTIONS") {
            let top = engine.history.topIntentions(5)
            if top.isEmpty {
                Text("Name your sessions to see where the time goes.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                VStack(spacing: 10) {
                    ForEach(top, id: \.name) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.name)
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(1)
                                Spacer()
                                Text(HistoryStore.hm(item.minutes))
                                    .font(.system(size: 11, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.white.opacity(0.08))
                                    Capsule().fill(glow.opacity(0.8))
                                        .frame(width: max(4, geo.size.width * CGFloat(item.minutes) / CGFloat(top[0].minutes)))
                                }
                            }
                            .frame(height: 4)
                        }
                    }
                }
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.4))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }
}
