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
    private let ambienceGenerator = AmbienceGenerator()
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
        let room = AmbienceNode.make(format: format, generator: ambienceGenerator)
        engine.attach(room)
        try? engine.connectNode(room, to: engine.mainMixerNode, format: format)
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

    /// The room sits well under the keys: it should be felt more than heard.
    private func updateAmbience() {
        ambienceGenerator.target = (ambience, isEnabled && ambience != .off ? 0.55 : 0)
    }

    /// Plays `kind` now. `pan` runs from -1 (left) to 1 (right) so keys sound where they sit.
    func play(_ kind: SoundKind, pan: Float = 0, gain: Float = 1) {
        guard isEnabled, let takes = bank[kind], !takes.isEmpty else { return }
        guard ensureRunning() else { return }
        // Never the same take twice in a row, so fast typing doesn't sound like a loop.
        var pick = Int.random(in: 0..<takes.count)
        if takes.count > 1, pick == lastPick[kind] { pick = (pick + 1) % takes.count }
        lastPick[kind] = pick

        let player = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        player.pan = max(-1, min(1, pan)) * 0.35
        player.volume = gain * Float.random(in: 0.86...1.0)
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

/// Builds every take of every sound for a machine, as raw mono samples.
nonisolated enum SoundBankBuilder {
    static func build(machine: MachineSound, sampleRate: Double) -> [SoundKind: [[Float]]] {
        var bank: [SoundKind: [[Float]]] = [:]
        for kind in SoundKind.allCases {
            if let recorded = RecordedSamples.load(machine: machine, kind: kind, sampleRate: sampleRate), !recorded.isEmpty {
                bank[kind] = recorded.flatMap { take in kind.rates.map { TypewriterSynth.resample(take, rate: $0) } }
                continue
            }
            var takes: [[Float]] = []
            for take in 0..<kind.takes {
                let seed = UInt64(abs(machine.rawValue.hashValueStable &+ kind.rawValue.hashValueStable &* 31 &+ take &* 977))
                var synth = TypewriterSynth(sampleRate: sampleRate, profile: machine.profile, seed: seed)
                let base = synth.render(kind)
                takes += kind.rates.map { TypewriterSynth.resample(base, rate: $0) }
            }
            bank[kind] = takes
        }
        return bank
    }
}

/// Real recordings, when they exist, replace the synthesized takes. Drop files named
/// `<machine>-<kind>-<n>.wav` (for example `portable-key-1.wav`) into the app bundle. They're read at launch,
/// never on a key press.
nonisolated enum RecordedSamples {
    static func load(machine: MachineSound, kind: SoundKind, sampleRate: Double) -> [[Float]]? {
        var takes: [[Float]] = []
        for n in 1...12 {
            let name = "\(machine.rawValue)-\(kind.rawValue)-\(n)"
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav")
                ?? Bundle.main.url(forResource: name, withExtension: "caf") else { break }
            if let samples = read(url, sampleRate: sampleRate) { takes.append(samples) }
        }
        return takes.isEmpty ? nil : takes
    }

    private static func read(_ url: URL, sampleRate: Double) -> [Float]? {
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
