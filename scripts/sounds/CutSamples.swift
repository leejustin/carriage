// Cuts Carriage's sound packs out of the real CC0 recordings in docs/sounds/SOURCES.md, and levels them so
// every machine plays at the same loudness.
//
//   swiftc -O scripts/sounds/CutSamples.swift -o /tmp/cut && /tmp/cut <folder of source .wav files> Carriage/Sounds
//
// Sources are decoded to 48 kHz mono float WAV first (afconvert -f WAVE -d LEF32@48000 -c 1 in.mp3 out.wav), and
// keep their Freesound ID as the file name.
import Accelerate
import AVFoundation

let args = CommandLine.arguments
let sourceFolder = URL(fileURLWithPath: args[1])
let outFolder = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: outFolder, withIntermediateDirectories: true)
let rate = 48_000.0

// MARK: Reading and writing

func read(_ id: String) -> [Float] {
    let url = sourceFolder.appendingPathComponent("\(id).wav")
    let file = try! AVAudioFile(forReading: url)
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try! file.read(into: buffer)
    var x = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    // Take out rumble and mains hum under 90 Hz, which turn into mud once levelled up.
    var y: Float = 0, prev: Float = 0
    let a = Float(1 / (1 + 2 * Double.pi * 90 / rate))
    for i in x.indices {
        y = a * (y + x[i] - prev)
        prev = x[i]
        x[i] = y
    }
    return x
}

func write(_ samples: [Float], name: String) {
    let url = outFolder.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: url)
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
                                   AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
    let file = try! AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(samples.count))!
    buffer.frameLength = AVAudioFrameCount(samples.count)
    for i in samples.indices { buffer.floatChannelData![0][i] = samples[i] }
    try! file.write(from: buffer)
}

func writeAAC(_ samples: [Float], name: String) {
    let wav = outFolder.appendingPathComponent(name + ".tmp.wav")
    write(samples, name: name + ".tmp.wav")
    let out = outFolder.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: out)
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
    task.arguments = ["-f", "m4af", "-d", "aac", "-b", "160000", wav.path, out.path]
    try! task.run()
    task.waitUntilExit()
    try? FileManager.default.removeItem(at: wav)
}

// MARK: Measuring

func rms(_ x: ArraySlice<Float>) -> Float {
    guard !x.isEmpty else { return 0 }
    var s: Float = 0
    for v in x { s += v * v }
    return (s / Float(x.count)).squareRoot()
}

func db(_ v: Float) -> Float { 20 * log10(max(v, 1e-9)) }

/// Scales a take so its attack sits at `target` dBFS RMS, without letting any peak past -1 dBFS.
func level(_ x: [Float], target: Float, window: Double) -> [Float] {
    let n = min(x.count, Int(window * rate))
    let current = db(rms(x[0..<n]))
    var gain = pow(10, (target - current) / 20)
    let peak = (x.map(abs).max() ?? 1) * gain
    if peak > 0.89 { gain *= 0.89 / peak }
    return x.map { $0 * gain }
}

/// A short fade in and a longer fade out, so nothing clicks.
func fades(_ x: [Float], inMs: Double = 1, outMs: Double = 40) -> [Float] {
    var y = x
    let fi = min(y.count, Int(inMs / 1000 * rate)), fo = min(y.count, Int(outMs / 1000 * rate))
    for i in 0..<fi { y[i] *= Float(i) / Float(fi) }
    for i in 0..<fo { y[y.count - 1 - i] *= Float(i) / Float(fo) }
    return y
}

/// The sample where the attack starts, searching from `t` seconds for `span` seconds.
func onset(in x: [Float], near t: Double, span: Double = 0.4) -> Int {
    let hop = Int(rate * 0.001)
    let a = max(0, Int(t * rate)), b = min(x.count - hop, Int((t + span) * rate))
    var best = a, bestRise: Float = 0
    var prev = rms(x[a..<(a + hop)])
    var i = a + hop
    while i < b {
        let cur = rms(x[i..<(i + hop)])
        if cur - prev > bestRise { bestRise = cur - prev; best = i }
        prev = cur
        i += hop
    }
    return max(0, best - Int(0.003 * rate))
}

/// Every isolated, strong keystroke: a sharp rise, nothing else loud for `after` seconds, quiet just before.
func keystrokes(in x: [Float], after: Double = 0.17) -> [Int] {
    let hop = Int(rate * 0.002)
    var env: [Float] = []
    var i = 0
    while i + hop <= x.count { env.append(rms(x[i..<(i + hop)])); i += hop }
    let floor = env.sorted()[env.count / 5]
    var onsets: [(Int, Float)] = []
    var last = -1000
    for k in 4..<(env.count - 1) where k - last > 30 {
        let before = max(env[k - 4], floor)
        if db(env[k]) - db(before) > 14, db(env[k]) - db(floor) > 22 {
            let peak = env[k..<min(env.count, k + 15)].max() ?? env[k]
            onsets.append((k, peak))
            last = k
        }
    }
    guard !onsets.isEmpty else { return [] }
    let loud = db(onsets.map(\.1).sorted()[onsets.count * 9 / 10])
    var picks: [Int] = []
    for (n, o) in onsets.enumerated() where db(o.1) > loud - 12 {
        let nextGap = n + 1 < onsets.count ? Double(onsets[n + 1].0 - o.0) * Double(hop) / rate : 1
        let prevGap = n > 0 ? Double(o.0 - onsets[n - 1].0) * Double(hop) / rate : 1
        guard nextGap > after, prevGap > 0.06 else { continue }
        picks.append(o.0 * hop)
    }
    return picks
}

/// How bright a take is: zero crossings per second over its first 40 ms.
func brightness(_ x: [Float]) -> Double {
    let n = min(x.count, Int(0.04 * rate))
    var zc = 0
    for i in 1..<n where (x[i] >= 0) != (x[i - 1] >= 0) { zc += 1 }
    return Double(zc) / 0.04
}

func cut(_ x: [Float], from a: Int, seconds: Double) -> [Float] {
    Array(x[a..<min(x.count, a + Int(seconds * rate))])
}

/// A keystroke from just before its strike, shaped to ring out naturally and stop before the next key or a
/// motor's drone can follow it: the first 20 ms as recorded, then a smooth decay.
func stroke(_ x: [Float], near a: Int) -> [Float] {
    // Start 3 ms before the sharpest rise within the first 120 ms, so the key sounds the moment it's pressed.
    let start = onset(in: x, near: Double(a) / rate - 0.005, span: 0.12)
    var y = cut(x, from: start, seconds: 0.22)
    let hold = Int(0.02 * rate), tau = 0.05 * rate
    for i in hold..<y.count { y[i] *= Float(exp(-Double(i - hold) / tau)) }
    return y
}

// MARK: Levels

// One loudness for every key on every machine, measured over the attack; the rest relative to it.
let keyLevel: Float = -24
let spaceLevel: Float = -25
let bellLevel: Float = -24
let returnLevel: Float = -24
let paperLevel: Float = -25
let roomLevel: Float = -34

// MARK: Machines

struct Machine {
    var name: String
    var source: String
    /// Where its own bell and carriage return are, if the recording has clear ones; otherwise the shared ones.
    var bell: (String, Double, Double)?
    var carriageReturn: (String, Double, Double)?
}

let sharedBell = ("345955_191884", 0.0, 0.9)
let sharedReturn = ("345955_191884", 1.65, 1.0)
let brightBell = ("318687_1147663", 0.0, 0.88)

let machines = [
    Machine(name: "portable", source: "123344_1848966", bell: nil, carriageReturn: nil),
    Machine(name: "upright", source: "519622_8147189", bell: nil, carriageReturn: nil),
    Machine(name: "electric", source: "224012_82274", bell: brightBell, carriageReturn: nil),
    Machine(name: "tin", source: "240839_2688492", bell: ("240839_2688492", 16.7, 1.0), carriageReturn: ("240839_2688492", 18.85, 1.05)),
]

var report: [String] = []
for machine in machines {
    let x = read(machine.source)
    let strokes = keystrokes(in: x)
    let takes = strokes.map { stroke(x, near: $0) }
    // The loudest strokes as keys; among the next loudest, the dullest as the space bar (its wide bar thuds).
    let byLoudness = takes.sorted { rms($0[0..<min($0.count, 2400)]) > rms($1[0..<min($1.count, 2400)]) }
    let keys = Array(byLoudness.prefix(14))
    let spaces = Array(byLoudness.dropFirst(14).prefix(30).sorted { brightness($0) < brightness($1) }.prefix(4))
    for (i, take) in keys.enumerated() {
        write(fades(level(take, target: keyLevel, window: 0.05)), name: "\(machine.name)-key-\(i + 1).wav")
    }
    for (i, take) in spaces.enumerated() {
        write(fades(level(take, target: spaceLevel, window: 0.05)), name: "\(machine.name)-space-\(i + 1).wav")
    }
    let bell = machine.bell ?? sharedBell
    let bx = bell.0 == machine.source ? x : read(bell.0)
    let ba = onset(in: bx, near: bell.1)
    write(fades(level(cut(bx, from: ba, seconds: bell.2), target: bellLevel, window: 0.3), outMs: 120), name: "\(machine.name)-bell-1.wav")
    let ret = machine.carriageReturn ?? sharedReturn
    let rx = ret.0 == machine.source ? x : read(ret.0)
    let ra = onset(in: rx, near: ret.1)
    write(fades(level(cut(rx, from: ra, seconds: ret.2), target: returnLevel, window: ret.2), outMs: 80), name: "\(machine.name)-carriageReturn-1.wav")
    report.append("\(machine.name): \(strokes.count) clean strokes found, \(keys.count) keys, \(spaces.count) space takes, bell from \(bell.0), return from \(ret.0)")
}

// MARK: Paper

// The Selectric recording loads a sheet at the start and rolls it out at the end; both are clear.
let selectric = read("224012_82274")
for name in machines.map(\.name) {
    write(fades(level(cut(selectric, from: Int(8.15 * rate), seconds: 1.05), target: paperLevel, window: 1.05), outMs: 150), name: "\(name)-paperFeed-1.wav")
    write(fades(level(cut(selectric, from: Int(110.55 * rate), seconds: 1.4), target: paperLevel, window: 1.4), outMs: 200), name: "\(name)-paperRelease-1.wav")
}

// MARK: Desk sounds

/// A seamless loop: `seconds` from `start`, its tail crossfaded into its head.
func loop(_ x: [Float], start: Double, seconds: Double, crossfade: Double = 2) -> [Float] {
    let a = Int(start * rate), n = Int(seconds * rate), f = Int(crossfade * rate)
    var body = Array(x[a..<(a + n)])
    let tail = Array(x[(a + n)..<(a + n + f)])
    for i in 0..<f {
        let w = Float(i) / Float(f)
        body[i] = body[i] * w + tail[i] * (1 - w)
    }
    return body
}
let rain = read("616530_97550")
writeAAC(level(loop(rain, start: 20, seconds: 40), target: roomLevel, window: 40), name: "desk-rain.m4a")
let fire = read("734248_2391840")
writeAAC(level(loop(fire, start: 60, seconds: 45), target: roomLevel + 2, window: 45), name: "desk-fire.m4a")

print(report.joined(separator: "\n"))
