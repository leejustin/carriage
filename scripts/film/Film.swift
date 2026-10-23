// The launch film's title cards and soundtrack: each card typed out letter by letter on the cream page, with the
// portable's real recorded keys under it, rain throughout, and the bell and carriage over the return shot.
//
//   swift scripts/film/Film.swift <work folder> <duo audio.wav>    (scripts/film/make.sh runs it)
//
// Writes <work>/card-N/frame-NNNN.png for each card and <work>/soundtrack.wav for the whole film, and prints the
// timeline make.sh cuts the pictures to.
import AppKit
import AVFoundation
import CoreText

let args = CommandLine.arguments
let work = URL(fileURLWithPath: args[1])
let duoAudio = URL(fileURLWithPath: args[2])
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
CTFontManagerRegisterFontsForURL(root.appendingPathComponent("Carriage/Fonts/CourierPrime-Regular.ttf") as CFURL, .process, nil)

let size = CGSize(width: 1920, height: 1080)
let fps = 30.0
let rate = 48_000.0

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// MARK: Timeline

enum Segment {
    case clip(String, Double)            // a Dreamina shot and how long it runs
    case card(String, perKey: Double, hold: Double)
    case duo(Double)                     // the real Duo recording
    case end(Double)
}

let duoLength = 23.5
let timeline: [Segment] = [
    .clip("find", 5),
    .card("I found my parents' old typewriter.", perKey: 0.085, hold: 1.1),
    .clip("typing", 5),
    .card("It made me slow down.", perKey: 0.13, hold: 1.3),
    .clip("return", 5),
    .card("So I rebuilt it for the iPhone Duo.", perKey: 0.085, hold: 1.0),
    .duo(duoLength),
    .end(5),
]

func length(_ segment: Segment) -> Double {
    switch segment {
    case let .clip(_, d), let .duo(d), let .end(d): d
    case let .card(text, perKey, hold): 0.5 + Double(text.count) * perKey + hold
    }
}

// MARK: Sound

func read(_ url: URL) -> [Float] {
    let file = try! AVAudioFile(forReading: url)
    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
    let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try! file.read(into: source)
    if file.processingFormat.sampleRate == rate, file.processingFormat.channelCount == 1 {
        return Array(UnsafeBufferPointer(start: source.floatChannelData![0], count: Int(source.frameLength)))
    }
    let converter = AVAudioConverter(from: file.processingFormat, to: format)!
    let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(source.frameLength) * rate / file.processingFormat.sampleRate) + 1024)!
    var fed = false
    converter.convert(to: out, error: nil) { _, status in
        if fed { status.pointee = .endOfStream; return nil }
        fed = true
        status.pointee = .haveData
        return source
    }
    return Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
}

let sounds = root.appendingPathComponent("Carriage/Sounds")
let keys = (1...14).map { read(sounds.appendingPathComponent("portable-key-\($0).wav")) }
let spaces = (1...4).map { read(sounds.appendingPathComponent("portable-space-\($0).wav")) }
let bell = read(sounds.appendingPathComponent("portable-bell-1.wav"))
let carriageReturn = read(sounds.appendingPathComponent("portable-carriageReturn-1.wav"))
let rain = read(sounds.appendingPathComponent("desk-rain.m4a"))
let duo = read(duoAudio)

let total = timeline.map(length).reduce(0, +)
var mix = [Float](repeating: 0, count: Int(total * rate) + 1)
func add(_ samples: [Float], at t: Double, gain: Float = 1) {
    let start = Int(t * rate)
    for (i, v) in samples.enumerated() where start + i < mix.count { mix[start + i] += v * gain }
}

// MARK: Cards

func paper(_ bounds: CGRect) {
    NSGradient(starting: color(0xF6F1E6), ending: color(0xE9DFCB))!.draw(in: bounds, angle: -90)
    NSGradient(colors: [color(0xFFF4D8, 0.8), color(0xFFF4D8, 0)])!
        .draw(fromCenter: CGPoint(x: bounds.width * 0.3, y: bounds.maxY), radius: 0, toCenter: CGPoint(x: bounds.width * 0.3, y: bounds.maxY), radius: bounds.height * 1.2, options: [])
}

func frame(_ draw: (CGRect) -> Void, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let ink = color(0x24211E)
let type = NSFont(name: "CourierPrime-Regular", size: 68)!
func typed(_ text: String) -> NSAttributedString {
    NSAttributedString(string: text, attributes: [.font: type, .foregroundColor: ink, .strokeWidth: -1.4, .strokeColor: ink])
}

var t = 0.0
var cardNumber = 0
for segment in timeline {
    let d = length(segment)
    switch segment {
    case let .card(text, perKey, _):
        cardNumber += 1
        let folder = work.appendingPathComponent("card-\(cardNumber)")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Laid out for the whole line, so the letters land where they'll stay instead of the line re-centring.
        let full = typed(text).size()
        let origin = CGPoint(x: (size.width - full.width) / 2, y: (size.height - full.height) / 2)
        let frames = Int(d * fps)
        for f in 0..<frames {
            let shown = min(text.count, max(0, Int(((Double(f) / fps) - 0.5) / perKey) + 1))
            frame({ bounds in
                paper(bounds)
                typed(String(text.prefix(shown))).draw(at: origin)
                if shown == text.count {
                    color(0xA22D27).setFill()
                    NSBezierPath(roundedRect: CGRect(x: size.width / 2 - 34, y: origin.y - 34, width: 68, height: 7), xRadius: 3.5, yRadius: 3.5).fill()
                }
            }, to: folder.appendingPathComponent(String(format: "frame-%04d.png", f)))
        }
        for (i, character) in text.enumerated() {
            let at = t + 0.5 + Double(i) * perKey
            if character == " " { add(spaces[i % spaces.count], at: at, gain: 0.8) } else { add(keys[(i * 5) % keys.count], at: at, gain: 0.85) }
        }
    case .clip("return", _):
        add(bell, at: t + 0.15, gain: 0.7)
        add(carriageReturn, at: t + 0.6, gain: 0.9)
    case .duo:
        add(duo, at: t)
    case .end:
        let folder = work.appendingPathComponent("card-end")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let icon = NSImage(contentsOf: root.appendingPathComponent("Carriage/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))!
        frame({ bounds in
            paper(bounds)
            let centred = NSMutableParagraphStyle()
            centred.alignment = .center
            NSGraphicsContext.saveGraphicsState()
            let iconRect = CGRect(x: bounds.midX - 80, y: 640, width: 160, height: 160)
            NSBezierPath(roundedRect: iconRect, xRadius: 36, yRadius: 36).addClip()
            icon.draw(in: iconRect)
            NSGraphicsContext.restoreGraphicsState()
            NSAttributedString(string: "Carriage", attributes: [.font: NSFont(name: "CourierPrime-Regular", size: 96)!, .foregroundColor: ink, .strokeWidth: -1.4, .strokeColor: ink, .paragraphStyle: centred])
                .draw(with: CGRect(x: 0, y: 500, width: bounds.width, height: 120), options: [.usesLineFragmentOrigin])
            color(0xA22D27).setFill()
            NSBezierPath(roundedRect: CGRect(x: bounds.midX - 40, y: 478, width: 80, height: 8), xRadius: 4, yRadius: 4).fill()
            NSAttributedString(string: "Write with intent.", attributes: [.font: NSFont(name: "CourierPrime-Regular", size: 52)!, .foregroundColor: ink, .paragraphStyle: centred])
                .draw(with: CGRect(x: 0, y: 380, width: bounds.width, height: 80), options: [.usesLineFragmentOrigin])
            NSAttributedString(string: "A TYPEWRITER FOR IPHONE DUO  ·  CARRIAGE.PAGES.DEV", attributes: [.font: NSFont(name: "Futura-Medium", size: 30)!, .foregroundColor: ink.withAlphaComponent(0.65), .kern: 5, .paragraphStyle: centred])
                .draw(with: CGRect(x: 0, y: 300, width: bounds.width, height: 50), options: [.usesLineFragmentOrigin])
        }, to: folder.appendingPathComponent("frame.png"))
    default:
        break
    }
    t += d
}

// Rain under everything but the Duo, which brings its own; eased in and out around it.
let duoStart = timeline.prefix { if case .duo = $0 { false } else { true } }.map(length).reduce(0, +)
for i in mix.indices {
    let s = Double(i) / rate
    var g: Double = 0.55
    g *= min(1, s / 1.5)                                                     // in from silence
    let duoEnd = duoStart + duoLength
    if s > duoStart - 0.8 && s < duoStart { g *= (duoStart - s) / 0.8 }       // out as the Duo comes in
    else if s >= duoStart && s <= duoEnd { g = 0 }
    else if s > duoEnd && s < duoEnd + 0.8 { g *= (s - duoEnd) / 0.8 }         // back in after it
    g *= min(1, (total - s) / 2)                                             // out to silence
    mix[i] += rain[i % rain.count] * Float(g)
}

let peak = max(1, mix.map(abs).max() ?? 1)
let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(mix.count))!
buffer.frameLength = AVAudioFrameCount(mix.count)
for i in mix.indices { buffer.floatChannelData![0][i] = mix[i] / peak * 0.95 }
let soundtrack = work.appendingPathComponent("soundtrack.wav")
try? FileManager.default.removeItem(at: soundtrack)
try AVAudioFile(forWriting: soundtrack, settings: format.settings).write(from: buffer)

// The timeline, for make.sh: kind, name, start, length.
t = 0
cardNumber = 0
for segment in timeline {
    let d = length(segment)
    switch segment {
    case let .clip(name, _): print("clip \(name) \(t) \(d)")
    case .card: cardNumber += 1; print("card card-\(cardNumber) \(t) \(d)")
    case .duo: print("duo duo \(t) \(d)")
    case .end: print("end card-end \(t) \(d)")
    }
    t += d
}
