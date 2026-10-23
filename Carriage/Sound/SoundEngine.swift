import AVFoundation
import os

/// Plays the machine. Every buffer is built or loaded up front; a key press only schedules a buffer that's
/// already in memory on a player that's already running, so the sound starts within the audio I/O buffer
/// (about 5 ms).
final class SoundEngine {
    static let shared = SoundEngine()

    var isEnabled = true { didSet { updateAmbience() } }
    var volume: Float = 0.85 {
        didSet {
            engine.mainMixerNode.outputVolume = volume
            updateAmbience()
        }
    }
    /// The sound of the room, under the keys.
    var ambience: Ambience = .off { didSet { updateAmbience() } }
    private var ambiencePlayer = AVAudioPlayerNode()
    private var ambienceLoops: [Ambience: AVAudioPCMBuffer] = [:]
    private var playingAmbience: Ambience = .off
    /// Play even with the ring/silent switch set to silent.
    var playsInSilentMode = false {
        didSet { if oldValue != playsInSilentMode { configureSession() } }
    }

    private(set) var machine: MachineSound = .portable

    private var engine = AVAudioEngine()
    private var configurationObserver: NSObjectProtocol?
    /// Failed starts aren't retried on every key press; that would put a slow call in front of each letter.
    private var lastStartAttempt: Date = .distantPast
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var bank: [SoundKind: [AVAudioPCMBuffer]] = [:]
    private var format: AVAudioFormat?
    private var lastPick: [SoundKind: Int] = [:]
    #if DEBUG
    fileprivate var previewLog: [PreviewSound]?
    #endif
    private var observers: [NSObjectProtocol] = []
    private let log = Logger(subsystem: "Carriage", category: "Sound")

    private static let voiceCount = 14

    private init() {}

    /// Sets up the session and engine and builds the bank for `machine`. Call once at launch.
    func start(machine: MachineSound) {
        configureSession()
        buildGraph()
        observe()
        load(machine)
    }

    /// Creates the engine and its voices. Also used after a media services reset, which kills the old engine.
    private func buildGraph() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        engine.stop()
        engine = AVAudioEngine()
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate > 0 ? sampleRate : 48_000, channels: 1)!
        let rateChanged = self.format?.sampleRate != format.sampleRate
        self.format = format
        voices = (0..<Self.voiceCount).map { _ in
            let player = AVAudioPlayerNode()
            engine.attach(player)
            try? engine.connectNode(player, to: engine.mainMixerNode, format: format)
            return player
        }
        nextVoice = 0
        ambiencePlayer = AVAudioPlayerNode()
        engine.attach(ambiencePlayer)
        try? engine.connectNode(ambiencePlayer, to: engine.mainMixerNode, format: format)
        ambienceLoops = [:]
        playingAmbience = .off
        engine.mainMixerNode.outputVolume = volume
        engine.prepare()
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.startEngine() }
        }
        startEngine()
        // Buffers are tied to the format; rebuild them if the hardware rate moved.
        if rateChanged, !bank.isEmpty { load(machine) }
    }

    /// Swaps the machine's voice. Builds the new bank off the main thread, then installs it.
    func load(_ machine: MachineSound) {
        self.machine = machine
        guard let sampleRate = format?.sampleRate else { return }
        Task.detached(priority: .userInitiated) {
            let samples = SoundBankBuilder.build(machine: machine, sampleRate: sampleRate)
            await MainActor.run {
                guard self.machine == machine, let format = self.format else { return }
                self.bank = samples.mapValues { takes in takes.compactMap { Self.buffer($0, format: format) } }
                self.lastPick = [:]
            }
        }
    }

    /// Plays a short demo of another machine without switching to it, for the shop.
    func preview(_ machine: MachineSound) {
        guard let sampleRate = format?.sampleRate else { return }
        let script: [(SoundKind, Double)] = [(.key, 0.05), (.key, 0.17), (.key, 0.3), (.space, 0.45), (.key, 0.57), (.key, 0.66),
                                             (.key, 0.79), (.bell, 0.95), (.carriageReturn, 1.15)]
        Task { [weak self] in
            // Synthesize off the main thread so the shop doesn't hitch.
            let samples = await Task.detached(priority: .userInitiated) {
                SoundBankBuilder.build(machine: machine, sampleRate: sampleRate)
            }.value
            guard let format = self?.format else { return }
            let demo = samples.mapValues { takes in takes.compactMap { Self.buffer($0, format: format) } }
            var elapsed = 0.0
            for (kind, delay) in script {
                try? await Task.sleep(for: .seconds(delay - elapsed))
                elapsed = delay
                if let take = demo[kind]?.randomElement() { self?.play(take) }
            }
        }
    }

    /// The desk sound loops seamlessly under the keys, at a level already set when it was cut.
    private func updateAmbience() {
        let wanted: Ambience = isEnabled ? ambience : .off
        guard wanted != playingAmbience else { return }
        playingAmbience = wanted
        ambiencePlayer.stop()
        guard wanted != .off, let format, ensureRunning() else { return }
        if ambienceLoops[wanted] == nil { ambienceLoops[wanted] = Self.loop(wanted, format: format) }
        guard let loop = ambienceLoops[wanted] else { return }
        ambiencePlayer.volume = 0.9
        ambiencePlayer.scheduleBuffer(loop, at: nil, options: [.loops])
        try? ambiencePlayer.playAudio()
    }

    private static func loop(_ ambience: Ambience, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: "desk-\(ambience.rawValue)", withExtension: "m4a"),
              let samples = RecordedSamples.read(url, sampleRate: format.sampleRate) else { return nil }
        return buffer(samples, format: format)
    }

    /// Plays `kind` now. `pan` runs from -1 (left) to 1 (right) so keys sound where they sit.
    func play(_ kind: SoundKind, pan: Float = 0, gain: Float = 1) {
        guard isEnabled, let takes = bank[kind], !takes.isEmpty else { return }
        // Never the same take twice in a row, so fast typing doesn't sound like a loop.
        var pick = Int.random(in: 0..<takes.count)
        if takes.count > 1, pick == lastPick[kind] { pick = (pick + 1) % takes.count }
        let level = gain * Float.random(in: 0.86...1.0)
        #if DEBUG
        previewLog?.append(PreviewSound(time: CACurrentMediaTime(), buffer: takes[pick], gain: level, pan: max(-1, min(1, pan)) * 0.35))
        #endif
        guard ensureRunning() else { return }
        lastPick[kind] = pick

        let player = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        player.pan = max(-1, min(1, pan)) * 0.35
        player.volume = level
        player.scheduleBuffer(takes[pick], at: nil, options: .interrupts)
        if !player.isPlaying { try? player.playAudio() }
    }

    private func play(_ buffer: AVAudioPCMBuffer) {
        guard ensureRunning() else { return }
        let player = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        player.pan = 0
        player.volume = 1
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { try? player.playAudio() }
    }

    // MARK: Engine and session

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(playsInSilentMode ? .playback : .ambient, mode: .default, options: [.mixWithOthers])
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            log.error("Audio session setup failed: \(error.localizedDescription)")
        }
    }

    private func ensureRunning() -> Bool {
        if engine.isRunning { return true }
        guard Date().timeIntervalSince(lastStartAttempt) > 1 else { return false }
        startEngine()
        return engine.isRunning
    }

    private func startEngine() {
        lastStartAttempt = Date()
        do {
            try engine.start()
            for voice in voices { try? voice.playAudio() }
            if playingAmbience != .off { try? ambiencePlayer.playAudio() }
        } catch {
            log.error("Audio engine failed to start: \(error.localizedDescription)")
        }
    }

    private func observe() {
        let center = NotificationCenter.default
        // After an interruption (a call, Siri), pick the session back up so the next key press sounds.
        observers.append(center.addObserver(forName: AVAudioSession.resumptionRecommendationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.configureSession()
                self?.startEngine()
            }
        })
        // A reset kills every audio object; build a new engine rather than restarting the dead one.
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.configureSession()
                self?.buildGraph()
            }
        })
    }

    private static func buffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }
}

/// Every take of every sound for a machine, as raw mono samples, from the recordings in the app.
nonisolated enum SoundBankBuilder {
    static func build(machine: MachineSound, sampleRate: Double) -> [SoundKind: [[Float]]] {
        var recordings: [SoundKind: [[Float]]] = [:]
        for kind in SoundKind.allCases {
            recordings[kind] = RecordedSamples.load(machine: machine, kind: kind, sampleRate: sampleRate)
                // A machine missing a sound uses the default machine's, so nothing is ever silent.
                ?? RecordedSamples.load(machine: .portable, kind: kind, sampleRate: sampleRate)
        }
        var bank: [SoundKind: [[Float]]] = [:]
        for kind in SoundKind.allCases {
            guard let takes = recordings[kind] ?? kind.standIn.flatMap({ recordings[$0] }) else { continue }
            var shaped = takes
            // Backspace is a lighter press than a full strike.
            if kind == .backspace { shaped = takes.map { $0.map { $0 * 0.6 } } }
            bank[kind] = shaped.flatMap { take in kind.rates.map { Resample.by($0, take) } }
        }
        return bank
    }
}

/// The recordings, named `<machine>-<kind>-<n>.wav` (for example `portable-key-1.wav`), made by
/// scripts/sounds/CutSamples.swift. They're read when a machine is chosen, never on a key press.
nonisolated enum RecordedSamples {
    static func load(machine: MachineSound, kind: SoundKind, sampleRate: Double) -> [[Float]]? {
        var takes: [[Float]] = []
        for n in 1...20 {
            let name = "\(machine.rawValue)-\(kind.rawValue)-\(n)"
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav")
                ?? Bundle.main.url(forResource: name, withExtension: "caf") else { break }
            if let samples = read(url, sampleRate: sampleRate) { takes.append(samples) }
        }
        return takes.isEmpty ? nil : takes
    }

    static func read(_ url: URL, sampleRate: Double) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url),
              let target = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: source)) != nil,
              let converter = AVAudioConverter(from: file.processingFormat, to: target) else { return nil }
        let ratio = sampleRate / file.processingFormat.sampleRate
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(source.frameLength) * ratio) + 64) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed {
                status.pointee = .endOfStream
                return nil
            }
            fed = true
            status.pointee = .haveData
            return source
        }
        guard error == nil, let channel = output.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}

#if DEBUG
/// One sound played while the App Store preview was being recorded.
struct PreviewSound {
    var time: CFTimeInterval
    var buffer: AVAudioPCMBuffer
    var gain: Float
    var pan: Float
}

extension SoundEngine {
    /// Starts noting every sound played, for the App Store preview: a simulator's screen recording is silent, so
    /// its soundtrack is put together afterwards from exactly what played.
    func startPreviewLog() { previewLog = [] }

    /// Mixes everything played since `startPreviewLog()` into a stereo WAV at `url`, time zero being the first
    /// sound, and returns when (in `CACurrentMediaTime`) that first sound played.
    @discardableResult
    func writePreviewLog(to url: URL) -> CFTimeInterval? {
        guard let log = previewLog, let first = log.first, let format = format else { return nil }
        previewLog = nil
        let rate = format.sampleRate
        let end = log.map { $0.time - first.time + Double($0.buffer.frameLength) / rate }.max() ?? 0
        let frames = Int((end + 0.5) * rate)
        var left = [Float](repeating: 0, count: frames), right = left
        for sound in log {
            guard let samples = sound.buffer.floatChannelData?[0] else { continue }
            let start = Int((sound.time - first.time) * rate)
            // Equal-power pan, as the mixer does it.
            let angle = (sound.pan + 1) * .pi / 4
            let l = cos(angle) * sound.gain, r = sin(angle) * sound.gain
            for i in 0..<Int(sound.buffer.frameLength) where start + i < frames {
                left[start + i] += samples[i] * l
                right[start + i] += samples[i] * r
            }
        }
        // The desk sound runs under everything, at the level it plays at in the app.
        if let loop = ambienceLoops[playingAmbience]?.floatChannelData?[0], let length = ambienceLoops[playingAmbience].map({ Int($0.frameLength) }), length > 0 {
            let gain = ambiencePlayer.volume
            for i in 0..<frames {
                let v = loop[i % length] * gain
                left[i] += v
                right[i] += v
            }
        }
        guard let stereo = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: AVAudioFrameCount(frames)),
              let file = try? AVAudioFile(forWriting: url, settings: stereo.settings) else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        let peak = max(1, (left + right).map(abs).max() ?? 1)
        for i in 0..<frames {
            buffer.floatChannelData![0][i] = left[i] / peak
            buffer.floatChannelData![1][i] = right[i] / peak
        }
        try? file.write(from: buffer)
        return first.time
    }
}
#endif

private extension String {
    /// `hashValue` changes every launch; this doesn't.
    nonisolated var hashValueStable: Int {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return Int(truncatingIfNeeded: hash & 0x7FFF_FFFF)
    }
}
