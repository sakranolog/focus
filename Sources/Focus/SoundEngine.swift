import AVFoundation
import Foundation
import AppKit

/// Fire-and-forget AppleScript runner (osascript subprocess; never blocks).
func runAppleScript(_ script: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try? process.run()
}

/// Drives the Spotify desktop app via Apple Events — no API keys needed.
enum SpotifyController {
    private static let bundleID = "com.spotify.client"

    private static var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    static func play(uri: String?) {
        let body: String
        if let uri, !uri.isEmpty {
            body = "try\nplay track \"\(uri)\"\non error\nplay\nend try"
        } else {
            body = "play"
        }
        let script = "tell application id \"\(bundleID)\"\n\(body)\nend tell"
        if isRunning {
            runAppleScript(script)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    runAppleScript(script)
                }
            }
        }
    }

    static func pause() {
        guard isRunning else { return }
        runAppleScript("tell application id \"\(bundleID)\" to pause")
    }
}

enum Soundscape: String, CaseIterable, Identifiable {
    case off, noise, rain, ocean

    var id: String { rawValue }

    var name: String {
        switch self {
        case .off: return "Silence"
        case .noise: return "Deep Noise"
        case .rain: return "Rainfall"
        case .ocean: return "Ocean"
        }
    }

    var symbol: String {
        switch self {
        case .off: return "speaker.slash"
        case .noise: return "waveform"
        case .rain: return "cloud.rain"
        case .ocean: return "water.waves"
        }
    }
}

enum ChimeKind { case sessionEnd, breakEnd, flow }

struct MusicTrack: Identifiable, Equatable {
    let name: String
    let url: URL
    var id: String { name }
}

/// Bundled loops (Contents/Resources/Music) plus anything the user drops into
/// ~/Library/Application Support/Focus/Music (user files override bundled names).
enum MusicLibrary {
    static var userDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Focus/Music", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func tracks() -> [MusicTrack] {
        var found: [String: MusicTrack] = [:]
        var dirs: [URL] = []
        if let bundleMusic = Bundle.main.resourceURL?.appendingPathComponent("Music") {
            dirs.append(bundleMusic)
        }
        dirs.append(userDir)
        let exts = ["caf", "m4a", "mp3", "wav", "aiff"]
        for dir in dirs {
            let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for url in items where exts.contains(url.pathExtension.lowercased()) {
                let name = url.deletingPathExtension().lastPathComponent
                found[name] = MusicTrack(name: name, url: url)
            }
        }
        return found.values.sorted { $0.name < $1.name }
    }

    static func track(named name: String) -> MusicTrack? {
        tracks().first { $0.name == name }
    }
}

/// Procedural soundscapes are synthesized live — zero assets, endless, gapless.
final class ScapeDSP {
    // Written from the main thread, read on the audio thread; races on these
    // scalars are benign (worst case: a parameter lands one buffer late).
    private(set) var kindRaw: Int32 = 0 // 0 off, 1 noise, 2 rain, 3 ocean
    var targetGain: Float = 0.5
    var sampleRate: Float = 48000

    private var gain: Float = 0
    private var seed: UInt32 = 22222
    private var brown: Float = 0
    private var lpBody: Float = 0
    private var lpHiss: Float = 0
    private var dropCountdown: Int = 4000
    private var dropEnv: Float = 0
    private var lfoPhase: Float = 0

    func setKind(_ k: Int32) {
        if k != kindRaw { gain = 0 } // fade the new texture in from silence
        kindRaw = k
    }

    private func white() -> Float {
        seed = seed &* 1664525 &+ 1013904223
        return Float(Int32(bitPattern: seed)) / Float(Int32.max)
    }

    func next() -> Float {
        let kind = kindRaw
        let w = white()
        var s: Float = 0
        switch kind {
        case 1: // deep brown noise
            brown += 0.02 * (w - brown)
            s = brown * 3.2
        case 2: // rainfall: airy hiss + low wash + random droplet patter
            lpHiss += 0.18 * (w - lpHiss)
            let hiss = (w - lpHiss) * 0.16
            lpBody += 0.035 * (w - lpBody)
            let body = lpBody * 1.1
            dropCountdown -= 1
            if dropCountdown <= 0 {
                dropCountdown = Int(2000 + abs(white()) * 14000)
                dropEnv = 0.5 + 0.4 * abs(white())
            }
            dropEnv *= 0.9992
            s = hiss + body + (w - lpHiss) * dropEnv * 0.35
        case 3: // ocean: brown noise under a slow swell
            brown += 0.015 * (w - brown)
            lfoPhase += 0.07 / sampleRate
            if lfoPhase > 1 { lfoPhase -= 1 }
            let swell = 0.55 + 0.45 * sinf(2 * .pi * lfoPhase)
            s = brown * 3.0 * swell
        default:
            s = 0
        }
        gain += (targetGain * (kind == 0 ? 0 : 1) - gain) * 0.0004
        return tanhf(s) * gain * 0.9
    }
}

final class SoundEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var source: AVAudioSourceNode!
    private let dsp = ScapeDSP()
    private var chimes: [ChimeKind: AVAudioPCMBuffer] = [:]
    private var musicPlayer: AVAudioPlayer?
    private var currentMusicURL: URL?
    private var volume: Float = 0.5

    init() {
        let outSR = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = outSR > 0 ? outSR : 48000
        dsp.sampleRate = Float(sampleRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

        let dsp = self.dsp
        source = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let v = dsp.next()
                for buffer in abl {
                    buffer.mData!.assumingMemoryBound(to: Float.self)[frame] = v
                }
            }
            return noErr
        }

        engine.attach(source)
        engine.attach(player)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        // Warm bell for focus end, rising two-note for break end, soft single note entering flow.
        chimes[.sessionEnd] = Self.makeChime(format: format,
                                             notes: [(392.00, 0.00, 2.2, 0.8),
                                                     (587.33, 0.02, 2.4, 0.5),
                                                     (783.99, 0.04, 2.0, 0.25)],
                                             duration: 3.0)
        chimes[.breakEnd] = Self.makeChime(format: format,
                                           notes: [(587.33, 0.00, 1.0, 0.7),
                                                   (880.00, 0.30, 1.6, 0.7)],
                                           duration: 2.4)
        chimes[.flow] = Self.makeChime(format: format,
                                       notes: [(329.63, 0.00, 1.5, 0.45)],
                                       duration: 2.0)
    }

    private func ensureRunning() {
        guard !engine.isRunning else { return }
        try? engine.start()
    }

    func playScape(_ scape: Soundscape) {
        stopMusic()
        let k: Int32
        switch scape {
        case .off: k = 0
        case .noise: k = 1
        case .rain: k = 2
        case .ocean: k = 3
        }
        dsp.setKind(k)
        if k != 0 { ensureRunning() }
    }

    func playMusic(_ url: URL) {
        dsp.setKind(0)
        if currentMusicURL == url, let p = musicPlayer, p.isPlaying { return }
        stopMusic()
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.numberOfLoops = -1
        p.volume = volume * 0.9
        p.play()
        musicPlayer = p
        currentMusicURL = url
    }

    private func stopMusic() {
        musicPlayer?.stop()
        musicPlayer = nil
        currentMusicURL = nil
    }

    func stopAll() {
        dsp.setKind(0)
        stopMusic()
    }

    func setVolume(_ v: Float) {
        volume = max(0, min(1, v))
        dsp.targetGain = volume
        musicPlayer?.volume = volume * 0.9
    }

    func chime(_ kind: ChimeKind) {
        ensureRunning()
        guard engine.isRunning, let buffer = chimes[kind] else { return }
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts])
        player.play()
    }

    /// Renders a bell-like chime: each note gets four inharmonic partials with faster decay up high.
    private static func makeChime(format: AVAudioFormat,
                                  notes: [(freq: Double, delay: Double, decay: Double, amp: Double)],
                                  duration: Double) -> AVAudioPCMBuffer? {
        let sr = format.sampleRate
        let frames = AVAudioFrameCount(duration * sr)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let partials: [(ratio: Double, amp: Double, decayScale: Double)] =
            [(1.0, 1.0, 1.0), (2.01, 0.4, 1.6), (3.02, 0.18, 2.2), (4.16, 0.08, 2.8)]

        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            var v = 0.0
            for n in notes {
                let tt = t - n.delay
                guard tt >= 0 else { continue }
                let attack = min(1, tt / 0.004)
                for p in partials {
                    v += n.amp * p.amp * attack * sin(2 * .pi * n.freq * p.ratio * tt) * exp(-tt * p.decayScale / n.decay)
                }
            }
            let sample = Float(v * 0.16)
            for ch in 0..<Int(format.channelCount) {
                buffer.floatChannelData![ch][i] = sample
            }
        }
        return buffer
    }
}
