// Bakes a music file into a seamless loop:
// finds the sustained region, trims intro/outro, equal-power crossfades the
// tail into the head, normalizes, and writes 16-bit PCM WAV.
// usage: swift LoopTool.swift input out.wav [crossfadeSec=3] [maxLoopSec=150]
import AVFoundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: LoopTool input out.wav [crossfadeSec] [maxLoopSec]")
    exit(1)
}
let inURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])
let cfSec = args.count > 3 ? (Double(args[3]) ?? 3.0) : 3.0
let maxSec = args.count > 4 ? (Double(args[4]) ?? 150.0) : 150.0

do {
    let file = try AVAudioFile(forReading: inURL)
    let fmt = file.processingFormat
    let sr = fmt.sampleRate
    let totalFrames = AVAudioFrameCount(file.length)
    guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: totalFrames) else { exit(2) }
    try file.read(into: buf)
    let n = Int(buf.frameLength)
    let ch = Int(fmt.channelCount)
    guard let data = buf.floatChannelData, n > Int(sr * 10) else {
        print("input too short")
        exit(3)
    }

    // RMS envelope, 250 ms windows, mono mix
    let win = Int(sr * 0.25)
    let wCount = n / win
    var rms = [Double](repeating: 0, count: wCount)
    for w in 0..<wCount {
        var acc = 0.0
        for i in (w * win)..<((w + 1) * win) {
            var s = 0.0
            for c in 0..<ch { s += Double(data[c][i]) }
            s /= Double(ch)
            acc += s * s
        }
        rms[w] = (acc / Double(win)).squareRoot()
    }
    let sortedRMS = rms.sorted()
    let ref = sortedRMS[min(wCount - 1, Int(Double(wCount) * 0.9))]
    let thr = ref * 0.35

    func sustained(from w: Int, need: Int) -> Bool {
        guard w + need <= wCount else { return false }
        for i in w..<(w + need) where rms[i] < thr { return false }
        return true
    }
    let need = 8 // 2 s of sustained level
    var startW = 0
    while startW < wCount, !sustained(from: startW, need: need) { startW += 1 }
    var endW = wCount
    while endW > startW, rms[endW - 1] < thr { endW -= 1 }
    if startW >= endW || Double(endW - startW) * 0.25 < 30 {
        startW = min(4, wCount / 10)
        endW = wCount - min(4, wCount / 10)
    }
    let start = startW * win
    var end = endW * win
    if Double(end - start) / sr > maxSec { end = start + Int(maxSec * sr) }

    let cf = min(Int(cfSec * sr), (end - start) / 3)
    let outLen = end - start - cf
    guard outLen > Int(sr * 5) else {
        print("usable region too small")
        exit(4)
    }

    guard let outBuf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(outLen)) else { exit(5) }
    outBuf.frameLength = AVAudioFrameCount(outLen)
    let out = outBuf.floatChannelData!
    for c in 0..<ch {
        for i in 0..<outLen { out[c][i] = data[c][start + cf + i] }
        for i in 0..<cf {
            let j = outLen - cf + i
            let t = Double(i) / Double(cf)
            let g1 = Float(cos(t * .pi / 2))
            let g2 = Float(sin(t * .pi / 2))
            out[c][j] = out[c][j] * g1 + data[c][start + i] * g2
        }
    }

    // Normalize peak to about -1 dBFS (never boost more than 4x)
    var peak: Float = 0
    for c in 0..<ch {
        for i in 0..<outLen { peak = max(peak, abs(out[c][i])) }
    }
    if peak > 0 {
        let gain = min(0.891 / peak, 4.0)
        if abs(gain - 1) > 0.01 {
            for c in 0..<ch {
                for i in 0..<outLen { out[c][i] *= gain }
            }
        }
    }

    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sr,
        AVNumberOfChannelsKey: ch,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
    ]
    let outFile = try AVAudioFile(forWriting: outURL, settings: settings)
    try outFile.write(from: outBuf)
    print(String(format: "loop %.1fs (region %.1f–%.1fs of %.1fs), peak %.2f",
                 Double(outLen) / sr, Double(start) / sr, Double(end) / sr, Double(n) / sr, peak))
} catch {
    print("error: \(error)")
    exit(9)
}
