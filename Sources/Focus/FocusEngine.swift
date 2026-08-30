import Foundation
import Observation
import AppKit
import CoreGraphics
import ServiceManagement
import UserNotifications

enum Phase: String, Codable {
    case focus, shortBreak, longBreak

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Break"
        case .longBreak: return "Long Break"
        }
    }
}

enum RunState { case idle, running, paused }

struct BlockedApp: Codable, Equatable, Identifiable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

struct FocusSettings: Codable {
    var focusMinutes: Int = 25
    var shortBreakMinutes: Int = 5
    var longBreakMinutes: Int = 15
    var sessionsPerCycle: Int = 4
    var autoStartBreaks: Bool = true
    var autoStartFocus: Bool = false
    var chimeOn: Bool = true
    var soundscapeRaw: String = "off"
    var soundscapeVolume: Double = 0.5
    var spotifyURI: String = ""
    var hideDockIcon: Bool = false
    var launchAtLogin: Bool = false
    var flowModeOn: Bool = true
    var motivationOn: Bool = true
    var shieldOn: Bool = false
    var standaloneShield: Bool = false
    var confirmAbort: Bool = true
    var blockedApps: [BlockedApp] = []
    var blockedSites: [String] = []
    var onboarded: Bool = false

    static func load() -> FocusSettings {
        guard let data = UserDefaults.standard.data(forKey: "settings"),
              let s = try? JSONDecoder().decode(FocusSettings.self, from: data) else {
            return FocusSettings()
        }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "settings")
        }
    }
}

// Resilient decoding: new fields fall back to defaults instead of wiping saved settings.
extension FocusSettings {
    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        if let v = try? c.decodeIfPresent(Int.self, forKey: .focusMinutes) { focusMinutes = v }
        if let v = try? c.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) { shortBreakMinutes = v }
        if let v = try? c.decodeIfPresent(Int.self, forKey: .longBreakMinutes) { longBreakMinutes = v }
        if let v = try? c.decodeIfPresent(Int.self, forKey: .sessionsPerCycle) { sessionsPerCycle = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .autoStartBreaks) { autoStartBreaks = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .autoStartFocus) { autoStartFocus = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .chimeOn) { chimeOn = v }
        if let v = try? c.decodeIfPresent(String.self, forKey: .soundscapeRaw) { soundscapeRaw = v }
        if let v = try? c.decodeIfPresent(Double.self, forKey: .soundscapeVolume) { soundscapeVolume = v }
        if let v = try? c.decodeIfPresent(String.self, forKey: .spotifyURI) { spotifyURI = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .hideDockIcon) { hideDockIcon = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) { launchAtLogin = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .flowModeOn) { flowModeOn = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .motivationOn) { motivationOn = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .shieldOn) { shieldOn = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .standaloneShield) { standaloneShield = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .confirmAbort) { confirmAbort = v }
        if let v = try? c.decodeIfPresent([BlockedApp].self, forKey: .blockedApps) { blockedApps = v }
        if let v = try? c.decodeIfPresent([String].self, forKey: .blockedSites) { blockedSites = v }
        if let v = try? c.decodeIfPresent(Bool.self, forKey: .onboarded) { onboarded = v }
    }
}

/// What plays during focus: nothing, a procedural soundscape, a bundled track, or Spotify.
enum SoundChoice: Equatable {
    case off
    case scape(Soundscape)
    case music(String)
    case spotify

    init(raw: String) {
        if raw == "spotify" {
            self = .spotify
        } else if raw.hasPrefix("music:") {
            self = .music(String(raw.dropFirst("music:".count)))
        } else if let s = Soundscape(rawValue: raw), s != .off {
            self = .scape(s)
        } else {
            self = .off
        }
    }

    var symbol: String {
        switch self {
        case .off: return "speaker.slash"
        case .scape(let s): return s.symbol
        case .music: return "music.note"
        case .spotify: return "music.note.list"
        }
    }
}

@MainActor
@Observable
final class FocusEngine {
    static let shared = FocusEngine()

    var phase: Phase = .focus
    var runState: RunState = .idle
    var completedInCycle: Int = 0
    var intention: String = ""
    var now: Date = Date()
    var overtimeStart: Date?
    var settings: FocusSettings {
        didSet {
            settings.save()
            applySettings()
        }
    }

    let history = HistoryStore()
    let sound = SoundEngine()

    private var endDate: Date?
    private var pausedRemaining: TimeInterval?
    private var timer: Timer?
    private var askedNotificationAuth = false
    private var nextMotivationAt: Date?

    private init() {
        settings = FocusSettings.load()
        sound.setVolume(Float(settings.soundscapeVolume))
    }

    var inFlow: Bool { overtimeStart != nil }

    var soundChoice: SoundChoice { SoundChoice(raw: settings.soundscapeRaw) }

    func setSound(raw: String) {
        let previous = soundChoice
        settings.soundscapeRaw = raw
        if previous == .spotify && soundChoice != .spotify {
            SpotifyController.pause()
        }
        refreshSound()
    }

    func refreshSound() {
        guard runState == .running && phase == .focus else {
            sound.stopAll()
            if soundChoice == .spotify { SpotifyController.pause() }
            return
        }
        switch soundChoice {
        case .off:
            sound.stopAll()
        case .scape(let s):
            sound.playScape(s)
        case .music(let name):
            if let track = MusicLibrary.track(named: name) {
                sound.playMusic(track.url)
            } else {
                sound.stopAll()
            }
        case .spotify:
            sound.stopAll()
            SpotifyController.play(uri: Self.normalizeSpotifyURI(settings.spotifyURI))
        }
    }

    /// "https://open.spotify.com/playlist/ID?si=…" → "spotify:playlist:ID"; passes spotify: URIs through.
    static func normalizeSpotifyURI(_ input: String) -> String? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("spotify:") { return s }
        if let url = URL(string: s), let host = url.host, host.contains("spotify.com") {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count >= 2 {
                return "spotify:\(parts[parts.count - 2]):\(parts[parts.count - 1])"
            }
        }
        return nil
    }

    // MARK: - Time math (endDate-based, so it survives sleep/App Nap)

    func duration(of p: Phase) -> TimeInterval {
        switch p {
        case .focus: return TimeInterval(settings.focusMinutes * 60)
        case .shortBreak: return TimeInterval(settings.shortBreakMinutes * 60)
        case .longBreak: return TimeInterval(settings.longBreakMinutes * 60)
        }
    }

    var total: TimeInterval { duration(of: phase) }

    func remaining(at date: Date) -> TimeInterval {
        switch runState {
        case .idle: return total
        case .paused: return pausedRemaining ?? total
        case .running: return max(0, endDate?.timeIntervalSince(date) ?? 0)
        }
    }

    func progress(at date: Date) -> Double {
        let t = total
        guard t > 0 else { return 0 }
        return min(1, max(0, 1 - remaining(at: date) / t))
    }

    func overtime(at date: Date) -> TimeInterval {
        guard let s = overtimeStart else { return 0 }
        return max(0, date.timeIntervalSince(s))
    }

    static func format(_ interval: TimeInterval) -> String {
        let s = Int(interval.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// What every timer surface shows: countdown normally, count-up ("+3:12") in flow overtime.
    func displayTime(at date: Date) -> String {
        if inFlow {
            let s = max(0, Int(overtime(at: date)))
            return String(format: "+%d:%02d", s / 60, s % 60)
        }
        return Self.format(remaining(at: date))
    }

    func displayProgress(at date: Date) -> Double {
        inFlow ? 1 : progress(at: date)
    }

    var menuTitle: String {
        switch runState {
        case .idle: return ""
        case .paused: return "⏸ " + Self.format(remaining(at: now))
        case .running: return displayTime(at: now)
        }
    }

    // MARK: - Controls

    func toggle() {
        if inFlow { finishFlow(); return }
        if runState == .running { pause() } else { start() }
    }

    func start() {
        let remain = (runState == .paused ? (pausedRemaining ?? total) : total)
        endDate = Date().addingTimeInterval(remain)
        pausedRemaining = nil
        overtimeStart = nil
        runState = .running
        now = Date()
        nextMotivationAt = phase == .focus ? Date().addingTimeInterval(6 * 60) : nil
        startTimer()
        refreshSound()
        requestNotificationAuthIfNeeded()
        DistractionShield.shared.sessionStateChanged()
    }

    func pause() {
        guard runState == .running, !inFlow else { return }
        pausedRemaining = remaining(at: Date())
        runState = .paused
        nextMotivationAt = nil
        MotivationController.shared.dismiss()
        stopTimer()
        refreshSound()
        DistractionShield.shared.sessionStateChanged()
    }

    func reset() {
        runState = .idle
        endDate = nil
        pausedRemaining = nil
        overtimeStart = nil
        nextMotivationAt = nil
        MotivationController.shared.dismiss()
        stopTimer()
        refreshSound()
        DistractionShield.shared.sessionStateChanged()
    }

    // MARK: - Confirm-aware entry points (all UI buttons route through these)

    private enum AbortKind {
        case skip, reset
        var verb: String { self == .skip ? "Skip" : "Reset" }
    }

    func skipTapped() {
        if inFlow { finishFlow(); return }
        if runState == .idle || !settings.confirmAbort {
            advance(completed: false)
            return
        }
        promptAbort(.skip)
    }

    func resetTapped() {
        if inFlow { finishFlow(); return }
        if runState == .idle || !settings.confirmAbort {
            reset()
            return
        }
        promptAbort(.reset)
    }

    private func promptAbort(_ kind: AbortKind) {
        let phaseSnapshot = phase
        let stateSnapshot = runState
        let elapsed = max(0, total - remaining(at: Date()))
        let elapsedMin = Int(elapsed / 60)
        let canLog = phase == .focus && elapsedMin >= 1

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        let phaseName = phase == .focus ? "focus session" : "break"
        alert.messageText = "\(kind.verb) this \(phaseName)?"
        if canLog {
            alert.informativeText = "You're \(Self.format(elapsed)) in. Want to log that time before moving on?"
            alert.addButton(withTitle: "Log \(elapsedMin) min & \(kind.verb.lowercased())")
            alert.addButton(withTitle: "Discard & \(kind.verb.lowercased())")
            alert.addButton(withTitle: "Cancel")
        } else {
            alert.informativeText = phase == .focus
                ? "Less than a minute in — nothing to log yet."
                : "You're \(Self.format(elapsed)) into your break."
            alert.addButton(withTitle: kind.verb)
            alert.addButton(withTitle: "Cancel")
        }
        let response = alert.runModal()

        // The session may have completed on its own while the dialog was up.
        guard phase == phaseSnapshot, runState == stateSnapshot else { return }

        if canLog {
            switch response {
            case .alertFirstButtonReturn:
                history.record(minutes: elapsedMin, intention: intention)
                applyAbort(kind)
            case .alertSecondButtonReturn:
                applyAbort(kind)
            default:
                break
            }
        } else if response == .alertFirstButtonReturn {
            applyAbort(kind)
        }
    }

    private func applyAbort(_ kind: AbortKind) {
        switch kind {
        case .skip: advance(completed: false)
        case .reset: reset()
        }
    }

    // MARK: - Flow mode

    /// Time since the user last typed, clicked, or scrolled. Permission-free.
    nonisolated static func secondsSinceLastInput() -> TimeInterval {
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]
        return types
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .infinity
    }

    private func enterFlow() {
        overtimeStart = Date()
        endDate = nil
        if settings.chimeOn { sound.chime(.flow) }
        notify(title: "In flow ⚡", body: "Timer's still rolling — break whenever you're ready.")
    }

    func finishFlow(discountingIdle idle: TimeInterval = 0) {
        guard let start = overtimeStart else { return }
        let extra = max(0, Date().timeIntervalSince(start) - idle)
        overtimeStart = nil
        advance(completed: true, overtimeMinutes: Int((extra / 60).rounded()))
    }

    // MARK: - Cycle

    private func tick() {
        now = Date()
        guard runState == .running else { return }
        if phase == .focus, settings.motivationOn,
           let nextM = nextMotivationAt, now >= nextM,
           inFlow || remaining(at: now) > 45 {
            nextMotivationAt = now.addingTimeInterval(6 * 60)
            MotivationController.shared.show(engine: self)
        }
        if let start = overtimeStart {
            let idle = Self.secondsSinceLastInput()
            if idle >= 120 {
                finishFlow(discountingIdle: idle)
            } else if now.timeIntervalSince(start) >= 30 * 60 {
                finishFlow()
            }
        } else if let end = endDate, now >= end {
            if phase == .focus && settings.flowModeOn && Self.secondsSinceLastInput() < 20 {
                enterFlow()
            } else {
                advance(completed: true)
            }
        }
    }

    private func advance(completed: Bool, overtimeMinutes: Int = 0) {
        let finished = phase
        overtimeStart = nil
        nextMotivationAt = nil
        MotivationController.shared.dismiss()
        stopTimer()
        endDate = nil
        pausedRemaining = nil
        sound.stopAll()

        let next: Phase
        if finished == .focus {
            if completed {
                completedInCycle += 1
                history.record(minutes: settings.focusMinutes + overtimeMinutes,
                               overtime: overtimeMinutes,
                               intention: intention)
            }
            let cycleDone = completedInCycle >= settings.sessionsPerCycle
            next = cycleDone ? .longBreak : .shortBreak
            if completed {
                if settings.chimeOn { sound.chime(.sessionEnd) }
                let flowNote = overtimeMinutes > 0 ? " (+\(overtimeMinutes) min in flow)" : ""
                notify(title: "Focus complete\(flowNote)",
                       body: cycleDone
                        ? "That's \(completedInCycle) in a row. Take a long break — you earned it."
                        : "Nice work. \(settings.shortBreakMinutes) minutes to recharge.")
            }
        } else {
            next = .focus
            if finished == .longBreak { completedInCycle = 0 }
            if completed {
                if settings.chimeOn { sound.chime(.breakEnd) }
                notify(title: "Break's over",
                       body: intention.isEmpty ? "Ready for the next round?" : "Back to: \(intention)")
            }
        }

        phase = next
        runState = .idle
        refreshSound()
        DistractionShield.shared.sessionStateChanged()
        let auto = completed && (next == .focus ? settings.autoStartFocus : settings.autoStartBreaks)
        if auto { start() }
    }

    /// Called on app termination: quietly banks any meaningful partial focus time.
    func logPartialOnQuit() {
        guard phase == .focus, runState == .running || runState == .paused else { return }
        let minutes: Int
        let overtimeMin: Int
        if inFlow {
            overtimeMin = Int(overtime(at: Date()) / 60)
            minutes = settings.focusMinutes + overtimeMin
        } else {
            overtimeMin = 0
            minutes = Int(max(0, total - remaining(at: Date())) / 60)
        }
        guard minutes >= 1 else { return }
        history.record(minutes: minutes, overtime: overtimeMin, intention: intention)
    }

    /// Debug/snapshot helper: pretend `seconds` have already elapsed.
    func debugFastForward(_ seconds: TimeInterval) {
        endDate = endDate?.addingTimeInterval(-seconds)
        now = Date()
    }

    // MARK: - Plumbing

    private func startTimer() {
        stopTimer()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func applySettings() {
        sound.setVolume(Float(settings.soundscapeVolume))
        _ = NSApp.setActivationPolicy(settings.hideDockIcon ? .accessory : .regular)
        DistractionShield.shared.sessionStateChanged()
        syncLoginItem()
    }

    private func syncLoginItem() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let service = SMAppService.mainApp
        if settings.launchAtLogin {
            if service.status != .enabled { try? service.register() }
        } else {
            if service.status == .enabled { try? service.unregister() }
        }
    }

    private func requestNotificationAuthIfNeeded() {
        guard !askedNotificationAuth, Bundle.main.bundleIdentifier != nil else { return }
        askedNotificationAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
