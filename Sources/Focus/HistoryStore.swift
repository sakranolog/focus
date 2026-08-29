import Foundation
import Observation

struct SessionRecord: Codable {
    let date: Date        // completion time
    let minutes: Int      // total focused minutes, including flow overtime
    let overtime: Int?    // flow-mode extension minutes, if any
    let intention: String
}

@MainActor
@Observable
final class HistoryStore {
    private(set) var records: [SessionRecord] = []

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Focus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    init() {
        if let data = try? Data(contentsOf: url),
           let recs = try? JSONDecoder().decode([SessionRecord].self, from: data) {
            records = recs
        }
    }

    func record(minutes: Int, overtime: Int = 0, intention: String) {
        records.append(SessionRecord(date: Date(),
                                     minutes: minutes,
                                     overtime: overtime == 0 ? nil : overtime,
                                     intention: intention))
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: url)
        }
    }

    static func hm(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    // MARK: - Today

    var todayCount: Int {
        records.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    var todayMinutes: Int {
        records.filter { Calendar.current.isDateInToday($0.date) }
            .map(\.minutes)
            .reduce(0, +)
    }

    /// Consecutive days (ending today or yesterday) with at least one session.
    var streakDays: Int {
        let cal = Calendar.current
        let days = Set(records.map { cal.startOfDay(for: $0.date) })
        var streak = 0
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) {
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        while days.contains(day) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    var summaryLine: String {
        if todayCount == 0 { return "No focus yet today" }
        var line = "\(todayCount) × focus · \(Self.hm(todayMinutes))"
        if streakDays > 1 { line += " · \(streakDays)d streak" }
        return line
    }

    // MARK: - Insights

    var totalSessions: Int { records.count }

    private var dayMinutes: [Date: Int] {
        let cal = Calendar.current
        var map: [Date: Int] = [:]
        for r in records {
            map[cal.startOfDay(for: r.date), default: 0] += r.minutes
        }
        return map
    }

    func weekMinutes(offset: Int) -> Int {
        let cal = Calendar.current
        guard let base = cal.date(byAdding: .weekOfYear, value: offset, to: Date()),
              let interval = cal.dateInterval(of: .weekOfYear, for: base) else { return 0 }
        return records.filter { interval.contains($0.date) }.map(\.minutes).reduce(0, +)
    }

    func flowMinutes(weekOffset: Int) -> Int {
        let cal = Calendar.current
        guard let base = cal.date(byAdding: .weekOfYear, value: weekOffset, to: Date()),
              let interval = cal.dateInterval(of: .weekOfYear, for: base) else { return 0 }
        return records.filter { interval.contains($0.date) }.map { $0.overtime ?? 0 }.reduce(0, +)
    }

    /// Columns (oldest → current week) of 7 daily minute totals; nil marks future days.
    func heatmap(weeks: Int) -> [[Int?]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: today) else { return [] }
        let map = dayMinutes
        var cols: [[Int?]] = []
        for w in stride(from: -(weeks - 1), through: 0, by: 1) {
            guard let weekStart = cal.date(byAdding: .weekOfYear, value: w, to: thisWeek.start) else { continue }
            var col: [Int?] = []
            for d in 0..<7 {
                guard let day = cal.date(byAdding: .day, value: d, to: weekStart) else { continue }
                col.append(day > today ? nil : (map[day] ?? 0))
            }
            cols.append(col)
        }
        return cols
    }

    /// Minutes focused, binned by the hour each session started.
    var hourHistogram: [Int] {
        var bins = Array(repeating: 0, count: 24)
        let cal = Calendar.current
        for r in records {
            let start = r.date.addingTimeInterval(-Double(r.minutes) * 60)
            bins[cal.component(.hour, from: start)] += r.minutes
        }
        return bins
    }

    var longestStreak: Int {
        let cal = Calendar.current
        let days = Set(records.map { cal.startOfDay(for: $0.date) }).sorted()
        var best = 0
        var current = 0
        var prev: Date?
        for day in days {
            if let p = prev,
               let expected = cal.date(byAdding: .day, value: 1, to: p),
               cal.isDate(day, inSameDayAs: expected) {
                current += 1
            } else {
                current = 1
            }
            best = max(best, current)
            prev = day
        }
        return best
    }

    func topIntentions(_ n: Int) -> [(name: String, minutes: Int)] {
        var map: [String: (name: String, minutes: Int)] = [:]
        for r in records {
            let trimmed = r.intention.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            let existing = map[key]
            map[key] = (name: existing?.name ?? trimmed, minutes: (existing?.minutes ?? 0) + r.minutes)
        }
        return map.values.sorted { $0.minutes > $1.minutes }.prefix(n).map { $0 }
    }

    /// In-memory demo data for snapshot renders. Never persisted.
    func seedDemo() {
        var recs: [SessionRecord] = []
        let cal = Calendar.current
        let intentions = ["Ship the focus app", "Deep work", "Customer emails", "Roadmap planning", "Design review"]
        for dayBack in 0..<112 {
            if (dayBack * 7) % 11 < 3 && dayBack != 0 { continue }
            guard let base = cal.date(byAdding: .day, value: -dayBack, to: Date()) else { continue }
            let n = 1 + (dayBack * 13) % 4
            for i in 0..<n {
                let hour = [9, 10, 11, 14, 15, 16, 21][(dayBack + i * 3) % 7]
                guard let d = cal.date(bySettingHour: hour, minute: 25, second: 0, of: base) else { continue }
                let ot = (i + dayBack) % 4 == 0 ? 8 : 0
                recs.append(SessionRecord(date: d,
                                          minutes: 25 + ot,
                                          overtime: ot == 0 ? nil : ot,
                                          intention: intentions[(dayBack + i) % 5]))
            }
        }
        records = recs
    }
}
